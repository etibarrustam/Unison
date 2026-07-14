import Foundation
import CoreAudio
import AudioToolbox
import os

// Shared with the realtime IO block. Gains swap under a lock held for
// nanoseconds; the diagnostics fields tear harmlessly.
final class SpatialRenderState: @unchecked Sendable {
    private var lock = os_unfair_lock()
    // Dense per-output-channel gains; channels without a speaker stay 0.
    private var gainL = [Float](repeating: 0, count: 64)
    private var gainR = [Float](repeating: 0, count: 64)
    // Spatial mode: Apple's spatial mixer renders instead of the gains.
    // The matrix stays configured underneath as the fallback path.
    private var mixer: SpatialMixerRenderer?

    func setMixer(_ m: SpatialMixerRenderer?) {
        os_unfair_lock_lock(&lock)
        mixer = m
        os_unfair_lock_unlock(&lock)
    }

    private func currentMixer() -> SpatialMixerRenderer? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return mixer
    }

    var hasMixer: Bool { currentMixer() != nil }

    var mixerDiag: String {
        guard let m = currentMixer() else { return "0" }
        return "1 mcb=\(m.cbHits) mcbPk=\(m.cbPeak) mauPk=\(m.auPeak) mmap=\(m.mapHits) \(m.paramDump())"
    }
    // Diagnostics, written by the IO thread and read by the debug timer.
    var cbCount: Int = 0
    var inPeak: Float = 0
    var outPeak: Float = 0
    var inBufs: Int = 0
    var inChans: Int = 0

    func setMatrix(_ matrix: [Int: (l: Double, r: Double)]) {
        var l = [Float](repeating: 0, count: 64)
        var r = [Float](repeating: 0, count: 64)
        for (ch, g) in matrix where ch < 64 {
            l[ch] = Float(g.l)
            r[ch] = Float(g.r)
        }
        os_unfair_lock_lock(&lock)
        gainL = l
        gainR = r
        os_unfair_lock_unlock(&lock)
    }

    func gains(_ ch: Int) -> (Float, Float) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard ch < 64 else { return (0, 0) }
        return (gainL[ch], gainR[ch])
    }

    // Runs on the HAL IO thread: mixes the tap's stereo input into every
    // output channel by its gains. Buffers keep the devices' native
    // interleaving, so channels are addressed with a stride.
    func render(input: UnsafePointer<AudioBufferList>,
                output: UnsafeMutablePointer<AudioBufferList>) {
        cbCount += 1
        let inABL = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        inBufs = inABL.count
        inChans = inABL.first.map { Int($0.mNumberChannels) } ?? 0
        var inL: UnsafeMutablePointer<Float32>?
        var inR: UnsafeMutablePointer<Float32>?
        var strideL = 1
        var strideR = 1
        var frames = 0
        var seen = 0
        for buf in inABL {
            guard seen < 2, let data = buf.mData?.assumingMemoryBound(to: Float32.self) else { continue }
            let ch = max(1, Int(buf.mNumberChannels))
            for c in 0..<ch where seen < 2 {
                if seen == 0 {
                    inL = data + c
                    strideL = ch
                    frames = Int(buf.mDataByteSize) / (4 * ch)
                } else {
                    inR = data + c
                    strideR = ch
                }
                seen += 1
            }
        }

        let outABL = UnsafeMutableAudioBufferListPointer(output)
        guard let l = inL, frames > 0 else {
            for buf in outABL {
                if let d = buf.mData { memset(d, 0, Int(buf.mDataByteSize)) }
            }
            return
        }
        let r = inR ?? l
        for f in 0..<frames {
            inPeak = max(inPeak, max(abs(l[f * strideL]), abs(r[f * strideR])))
        }

        if let m = currentMixer(),
           let peak = m.render(inL: l, strideL: strideL, inR: r, strideR: strideR,
                               frames: frames, output: outABL) {
            outPeak = max(outPeak, peak)
            return
        }

        var chIndex = 0
        for buf in outABL {
            let ch = max(1, Int(buf.mNumberChannels))
            guard let data = buf.mData?.assumingMemoryBound(to: Float32.self) else {
                chIndex += ch
                continue
            }
            let bufFrames = Int(buf.mDataByteSize) / (4 * ch)
            let n = min(frames, bufFrames)
            for c in 0..<ch {
                let (gl, gr) = gains(chIndex + c)
                if gl == 0 && gr == 0 {
                    for f in 0..<bufFrames { data[f * ch + c] = 0 }
                    continue
                }
                for f in 0..<n {
                    let v = gl * l[f * strideL] + gr * r[f * strideR]
                    data[f * ch + c] = v
                    outPeak = max(outPeak, abs(v))
                }
                for f in n..<bufFrames { data[f * ch + c] = 0 }
            }
            chIndex += ch
        }
    }
}

// One entry per physical output device, for the membership toggles.
struct SpatialOutputDevice: Identifiable {
    let uid: String
    let name: String
    var id: String { uid }
}

@MainActor
final class SpatialEngine: ObservableObject {
    static let aggregateUID = "com.unison.spatial.aggregate"
    // The selectable "Unison" entry in the Sound output list. Picking it
    // routes audio into the tap; picking any real device routes around us.
    static let publicUID = "com.unison.output"

    private let state = SpatialRenderState()
    private var aggregateID = AudioDeviceID(0)
    private var publicID = AudioDeviceID(0)
    private var tapID = AudioObjectID(0)
    private var tapUUID = ""
    private var procID: AudioDeviceIOProcID?
    @Published private(set) var isRunning = false
    // True after a tap creation failure, which in practice means macOS
    // denied the System Audio Recording permission.
    @Published private(set) var captureDenied = false
    private var deviceOrder: [String] = []
    private var channelCounts: [String: Int] = [:]
    private var excluded: Set<String> = []
    private var debugTimer: Timer?
    private var mixerWork: DispatchWorkItem?

    // Every real output device, including excluded ones, so the settings
    // UI can offer re-inclusion.
    func outputDeviceList() -> [SpatialOutputDevice] {
        realOutputDevices().map { SpatialOutputDevice(uid: $0.uid, name: $0.name) }
    }

    // Every channel of every included output device. The default position
    // is the channel's natural stereo side, never center: a room full of
    // coincident center speakers is a degenerate layout the spatial mixer
    // cannot render, and natural stereo is the right starting sound anyway.
    func availableSpeakers() -> [SpatialSpeaker] {
        includedOutputDevices().flatMap { dev in
            (1...dev.channels).map { ch in
                let side = dev.channels == 2 ? (ch == 1 ? "Left" : "Right") : "Ch \(ch)"
                let natural = dev.channels == 2 ? (ch == 1 ? 0.0 : 1.0) : 0.5
                return SpatialSpeaker(deviceUID: dev.uid, channel: ch,
                                      name: "\(dev.name) \(side)", position: natural)
            }
        }
    }

    // True when a device joined or left since the last start. The watcher
    // uses this so our own aggregate churn never triggers a rebuild loop.
    func realDevicesChanged() -> Bool {
        let current = allOutputDevicesSorted()
        return current.map(\.uid) != deviceOrder
            || Dictionary(uniqueKeysWithValues: current.map { ($0.uid, $0.channels) }) != channelCounts
    }

    // placements nil means passthrough: no positioning, every device keeps
    // its natural stereo. The engine runs either way, because it is the
    // only path that plays through more than one device at once.
    // Exclusions only shape the mix; the aggregate always holds every
    // real output, so play-through toggles never rebuild anything.
    func start(placements: [String: [Double]]?, excluded: Set<String>) -> Bool {
        teardownIO()
        isRunning = false
        self.excluded = excluded

        let devices = allOutputDevicesSorted()
        guard !devices.isEmpty else { return false }
        deviceOrder = devices.map(\.uid)
        channelCounts = Dictionary(uniqueKeysWithValues: devices.map { ($0.uid, $0.channels) })

        guard ensureTap() else { return false }

        // A public aggregate survives a crashed owner; a leftover with our
        // UID must go before a new one can take its place.
        if let stale = deviceID(uidContains: Self.aggregateUID) {
            AudioHardwareDestroyAggregateDevice(stale)
        }

        // Aggregate: every real output plus the tap as input. Private:
        // a public aggregate cannot bind a private tap (no input streams
        // appear), and nothing needs to select this device anyway; the
        // public Unison device is the one users select.
        var subs: [[String: Any]] = []
        for (i, d) in devices.enumerated() {
            var sub: [String: Any] = [kAudioSubDeviceUIDKey as String: d.uid]
            if i > 0 { sub[kAudioSubDeviceDriftCompensationKey as String] = 1 }
            subs.append(sub)
        }
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Unison Spatial",
            kAudioAggregateDeviceUIDKey as String: Self.aggregateUID,
            kAudioAggregateDeviceSubDeviceListKey as String: subs,
            kAudioAggregateDeviceMainSubDeviceKey as String: devices[0].uid,
            kAudioAggregateDeviceTapListKey as String:
                [[kAudioSubTapUIDKey as String: tapUUID]],
            kAudioAggregateDeviceIsPrivateKey as String: 1,
            kAudioAggregateDeviceIsStackedKey as String: 0
        ]
        var aggID = AudioDeviceID(0)
        guard AudioHardwareCreateAggregateDevice(desc as CFDictionary, &aggID) == noErr else {
            teardownIO()
            return false
        }
        aggregateID = aggID
        usleep(150_000)  // aggregate needs a moment to publish streams

        guard setupIOProc(aggID) else {
            teardownIO()
            return false
        }

        applyMix(placements: placements)
        isRunning = true
        startDebugDump()
        NSLog("Unison: spatial engine started, \(devices.count) devices")
        return true
    }

    func stop() {
        teardownIO()
        // The tap and the Sound list entry outlive every engine rebuild;
        // only a full stop removes them. macOS falls back to a real
        // device when the default output vanishes.
        if tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }
        if publicID != 0 {
            AudioHardwareDestroyAggregateDevice(publicID)
            publicID = 0
        }
        if isRunning {
            isRunning = false
            NSLog("Unison: spatial engine stopped")
        }
    }

    // Play-through toggles: reshape the mix in place. Nothing is torn
    // down, so the toggle is instant and cannot race coreaudiod.
    func setExcluded(_ excluded: Set<String>, placements: [String: [Double]]?) {
        self.excluded = excluded
        applyMix(placements: placements)
    }

    // Stops IO and drops the private aggregate, keeping the tap. The tap
    // is created once per app run: recreating it right after destroying
    // its predecessor can leave the new tap silent while the mute still
    // applies, which was the play-through toggle bug.
    private func teardownIO() {
        debugTimer?.invalidate()
        debugTimer = nil
        // A rebuilt aggregate renumbers channels; the matrix carries the
        // gap until applyMix swaps a matching mixer back in.
        mixerWork?.cancel()
        state.setMixer(nil)
        if let procID, aggregateID != 0 {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = 0
        }
    }

    // Tap only what the system sends to the public Unison device and
    // mute it there, so the Sound list stays honest: picking a real
    // device plays natively, picking Unison feeds the engine. Our own
    // process is excluded so the re-rendered mix does not feed back
    // into the tap. Reading the tap needs the System Audio Recording
    // permission, not the microphone one. If the public device cannot
    // be made, fall back to the old global tap so sound still works.
    private func ensureTap() -> Bool {
        if tapID != 0 { return true }
        let tapDesc: CATapDescription
        if ensurePublicDevice() {
            tapDesc = CATapDescription(excludingProcesses: [ownProcessObject()],
                                       deviceUID: Self.publicUID, stream: 0)
        } else {
            NSLog("Unison: public device unavailable, falling back to global tap")
            tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcessObject()])
        }
        tapDesc.muteBehavior = .mutedWhenTapped
        tapDesc.name = "Unison Spatial Tap"
        tapDesc.isPrivate = true
        var tap = AudioObjectID(0)
        let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &tap)
        guard tapStatus == noErr, tap != 0 else {
            captureDenied = true
            NSLog("Unison: process tap creation failed (\(tapStatus))")
            return false
        }
        captureDenied = false
        tapID = tap
        tapUUID = tapDesc.uuid.uuidString
        return true
    }

    func applyMix(placements: [String: [Double]]?) {
        var speakers = availableSpeakers()
        var chans: [SpatialMixerRenderer.SpeakerChannel] = []
        if let placements {
            var offsets: [String: Int] = [:]
            var next = 0
            for uid in deviceOrder {
                offsets[uid] = next
                next += channelCounts[uid] ?? 0
            }
            speakers = speakers.map { s in
                var m = s
                let p = placements[s.id].flatMap { $0.count == 2 ? $0 : nil }
                    ?? defaultPlacement(s)
                let az = SpatialMix.azimuth(x: p[0], y: p[1])
                // Matrix fallback approximates the placement as a pan;
                // sine folds rear angles onto the correct side.
                m.position = LevelMath.clamp(0.5 + sin(Double(az) * .pi / 180) / 2)
                if let base = offsets[s.deviceUID] {
                    chans.append(SpatialMixerRenderer.SpeakerChannel(
                        aggregateChannel: base + s.channel - 1,
                        azimuth: az,
                        distance: Float(SpatialMix.distance(x: p[0], y: p[1]))))
                }
                return m
            }
        }
        // The matrix is always configured: it is the stereo path and the
        // live fallback whenever the spatial mixer cannot render.
        state.setMatrix(SpatialMix.matrix(speakers: speakers,
                                          deviceOrder: deviceOrder,
                                          channelCounts: channelCounts,
                                          outputOffset: 0))
        rebuildMixer(chans: placements != nil ? chans : nil)
    }

    // The natural stereo triangle: left and right 30 degrees off center,
    // one and a half meters away. Other channel counts sit front center.
    func defaultPlacement(_ s: SpatialSpeaker) -> [Double] {
        guard channelCounts[s.deviceUID] == 2 else { return [0, 1.5] }
        return [s.channel == 1 ? -0.75 : 0.75, 1.3]
    }

    // Debounced: dot drags call applyMix on every tick, and the mixer's
    // output layout only changes through a full AU rebuild. The matrix
    // keeps rendering until the fresh mixer swaps in.
    private func rebuildMixer(chans: [SpatialMixerRenderer.SpeakerChannel]?) {
        mixerWork?.cancel()
        guard let chans, aggregateID != 0 else {
            state.setMixer(nil)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.aggregateID != 0 else { return }
                let renderer = SpatialMixerRenderer(speakers: chans,
                                                    sampleRate: self.aggregateSampleRate())
                self.state.setMixer(renderer.ready ? renderer : nil)
            }
        }
        mixerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func aggregateSampleRate() -> Double {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard aggregateID != 0,
              AudioObjectGetPropertyData(aggregateID, &addr, 0, nil, &size, &rate) == noErr,
              rate > 0 else { return 48000 }
        return rate
    }

    // Hidden diagnostics: defaults write com.unison.app unison.spatialDebug
    // -bool true, then read /tmp/unison-spatial.log.
    private func startDebugDump() {
        guard UserDefaults.standard.bool(forKey: "unison.spatialDebug") else { return }
        let s = state
        let order = deviceOrder
        debugTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            let line = "\(Date()) cb=\(s.cbCount) inPeak=\(s.inPeak) outPeak=\(s.outPeak) inBufs=\(s.inBufs) inChans=\(s.inChans) mixer=\(s.mixerDiag) order=\(order)\n"
            s.inPeak = 0
            s.outPeak = 0
            if let data = line.data(using: .utf8),
               let fh = FileHandle(forWritingAtPath: "/tmp/unison-spatial.log") {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            } else {
                try? line.write(toFile: "/tmp/unison-spatial.log", atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - CoreAudio plumbing

    private struct OutputDevice {
        let id: AudioDeviceID
        let uid: String
        let name: String
        let channels: Int
        let isBuiltin: Bool
    }

    private func realOutputDevices() -> [OutputDevice] {
        let audio = AudioController()
        return audio.outputDevices()
            .filter { !$0.isVirtualOrAggregate && !$0.uid.contains("BlackHole") }
            .compactMap { out in
                let ch = outputChannels(out.id)
                guard ch > 0 else { return nil }
                return OutputDevice(id: out.id, uid: out.uid, name: out.name,
                                    channels: ch, isBuiltin: out.isBuiltin)
            }
    }

    // The public device the user selects as sound output. Anchored to the
    // built-in output so its composition never changes on hot-plug: what
    // reaches it is muted by the tap, so membership does not affect what
    // plays where, but a stable composition keeps the Sound list selection
    // from bouncing across engine restarts.
    private func ensurePublicDevice() -> Bool {
        if publicID != 0 { return true }
        if let existing = deviceID(uidContains: Self.publicUID) {
            // Left over from a crashed instance: adopt it and keep the
            // user's current selection rather than churning the default.
            publicID = existing
            return true
        }
        let devices = realOutputDevices()
        guard let anchor = devices.first(where: \.isBuiltin) ?? devices.first else { return false }
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Unison",
            kAudioAggregateDeviceUIDKey as String: Self.publicUID,
            kAudioAggregateDeviceSubDeviceListKey as String:
                [[kAudioSubDeviceUIDKey as String: anchor.uid]],
            kAudioAggregateDeviceMainSubDeviceKey as String: anchor.uid,
            kAudioAggregateDeviceIsPrivateKey as String: 0,
            kAudioAggregateDeviceIsStackedKey as String: 0
        ]
        var id = AudioDeviceID(0)
        guard AudioHardwareCreateAggregateDevice(desc as CFDictionary, &id) == noErr, id != 0 else {
            return false
        }
        publicID = id
        usleep(150_000)  // let the new device publish before the tap targets it
        // Selected once, on the very first run after install, so the app
        // works out of the box. Every later launch respects whatever the
        // user picked in the Sound settings.
        if !UserDefaults.standard.bool(forKey: "unison.autoSelectedOutput") {
            UserDefaults.standard.set(true, forKey: "unison.autoSelectedOutput")
            setDefaultOutput(id)
        }
        NSLog("Unison: public output device created")
        return true
    }

    // The real device the Sound list currently points at, or nil while it
    // points at our public device (or the public device does not exist),
    // which callers treat as "all devices".
    func activeOutput() -> (uid: String, name: String)? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                         0, nil, &size, &dev) == noErr,
              dev != 0, publicID != 0, dev != publicID else { return nil }
        guard let out = AudioController().outputDevices().first(where: { $0.id == dev }) else { return nil }
        return (out.uid, out.name)
    }

    private func setDefaultOutput(_ id: AudioDeviceID) {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v = id
        _ = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                       UInt32(MemoryLayout<AudioDeviceID>.size), &v)
    }

    // Sorted by UID: CoreAudio enumeration order shuffles when unrelated
    // devices come and go, and a shuffle must not look like a hot-plug.
    private func allOutputDevicesSorted() -> [OutputDevice] {
        realOutputDevices().sorted { $0.uid < $1.uid }
    }

    private func includedOutputDevices() -> [OutputDevice] {
        allOutputDevicesSorted().filter { !excluded.contains($0.uid) }
    }

    private func setupIOProc(_ agg: AudioDeviceID) -> Bool {
        let s = state
        var pid: AudioDeviceIOProcID?
        // @Sendable: the block runs on the HAL IO thread and must not
        // inherit this method's main-actor isolation, or the runtime
        // isolation check traps on the first callback.
        let block: AudioDeviceIOBlock = { @Sendable _, inData, _, outData, _ in
            s.render(input: inData, output: outData)
        }
        let status = AudioDeviceCreateIOProcIDWithBlock(&pid, agg, nil, block)
        guard status == noErr, let pid else { return false }
        procID = pid
        guard AudioDeviceStart(agg, pid) == noErr else {
            AudioDeviceDestroyIOProcID(agg, pid)
            procID = nil
            return false
        }
        return true
    }

    private func ownProcessObject() -> AudioObjectID {
        var pid = pid_t(ProcessInfo.processInfo.processIdentifier)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var obj = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        withUnsafeMutablePointer(to: &pid) { p in
            _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                           UInt32(MemoryLayout<pid_t>.size), p, &size, &obj)
        }
        return obj
    }

    private func outputChannels(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size)
        guard size > 0 else { return 0 }
        let bl = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { bl.deallocate() }
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, bl)
        let list = UnsafeMutableAudioBufferListPointer(bl.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func deviceID(uidContains fragment: String) -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids.first { uid($0)?.contains(fragment) == true }
    }

    private func uid(_ id: AudioDeviceID) -> String? {
        guard id != 0 else { return nil }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var cf: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cf) == noErr, let cf else { return nil }
        return cf.takeRetainedValue() as String
    }

}
