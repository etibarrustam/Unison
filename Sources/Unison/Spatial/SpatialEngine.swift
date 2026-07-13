import Foundation
import CoreAudio
import AudioToolbox
import os

// Shared with the realtime render callback. Only this box is touched from
// the audio thread; gains swap under a lock held for nanoseconds.
final class SpatialRenderState: @unchecked Sendable {
    var unit: AudioUnit?
    var inputABL: UnsafeMutableAudioBufferListPointer?
    var maxFrames: Int = 4096
    var totalOutputChannels: Int = 0
    private var lock = os_unfair_lock()
    // Dense per-output-channel gains; channels without a speaker stay 0.
    private var gainL = [Float](repeating: 0, count: 64)
    private var gainR = [Float](repeating: 0, count: 64)

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
}

private func spatialRender(_ refCon: UnsafeMutableRawPointer,
                           _ ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                           _ inTimeStamp: UnsafePointer<AudioTimeStamp>,
                           _ inBusNumber: UInt32,
                           _ inNumberFrames: UInt32,
                           _ ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    let state = Unmanaged<SpatialRenderState>.fromOpaque(refCon).takeUnretainedValue()
    guard let unit = state.unit, let ioData,
          let inputABL = state.inputABL, inNumberFrames <= state.maxFrames else { return noErr }

    // Reset the reusable input buffers to full capacity before rendering.
    for i in 0..<inputABL.count {
        inputABL[i].mDataByteSize = UInt32(state.maxFrames * MemoryLayout<Float32>.size)
    }
    let status = AudioUnitRender(unit, ioActionFlags, inTimeStamp, 1, inNumberFrames, inputABL.unsafeMutablePointer)
    let out = UnsafeMutableAudioBufferListPointer(ioData)
    guard status == noErr, inputABL.count >= 2,
          let inL = inputABL[0].mData?.assumingMemoryBound(to: Float32.self),
          let inR = inputABL[1].mData?.assumingMemoryBound(to: Float32.self) else {
        for i in 0..<out.count {
            if let d = out[i].mData { memset(d, 0, Int(out[i].mDataByteSize)) }
        }
        return noErr
    }

    let n = Int(inNumberFrames)
    for ch in 0..<out.count {
        guard let d = out[ch].mData?.assumingMemoryBound(to: Float32.self) else { continue }
        let (gl, gr) = state.gains(ch)
        if gl == 0 && gr == 0 {
            memset(d, 0, n * MemoryLayout<Float32>.size)
            continue
        }
        for f in 0..<n {
            d[f] = gl * inL[f] + gr * inR[f]
        }
    }
    return noErr
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
    private static let prevOutputKey = "unison.spatial.prevOutput"

    private let state = SpatialRenderState()
    private var aggregateID = AudioDeviceID(0)
    @Published private(set) var isRunning = false
    private var deviceOrder: [String] = []
    private var channelCounts: [String: Int] = [:]
    private var excluded: Set<String> = []
    private var pinBlock: AudioObjectPropertyListenerBlock?

    var blackHoleInstalled: Bool { deviceID(uidContains: "BlackHole") != nil }

    // Every real output device, including excluded ones, so the settings
    // UI can offer re-inclusion.
    func outputDeviceList() -> [SpatialOutputDevice] {
        realOutputDevices().map { SpatialOutputDevice(uid: $0.uid, name: $0.name) }
    }

    // Every channel of every included output device except the loopback.
    func availableSpeakers() -> [SpatialSpeaker] {
        includedOutputDevices().flatMap { dev in
            (1...dev.channels).map { ch in
                let side = dev.channels == 2 ? (ch == 1 ? "Left" : "Right") : "Ch \(ch)"
                return SpatialSpeaker(deviceUID: dev.uid, channel: ch,
                                      name: "\(dev.name) \(side)", position: 0.5)
            }
        }
    }

    // True when a device joined or left since the last start. The watcher
    // uses this so our own aggregate churn never triggers a rebuild loop.
    func realDevicesChanged() -> Bool {
        let current = includedOutputDevices()
        return current.map(\.uid) != deviceOrder
            || Dictionary(uniqueKeysWithValues: current.map { ($0.uid, $0.channels) }) != channelCounts
    }

    func start(positions: [String: Double], excluded: Set<String>) -> Bool {
        let wasRunning = isRunning
        teardown()
        isRunning = false
        self.excluded = excluded

        func fail() -> Bool {
            if wasRunning { restorePreviousOutput() }
            return false
        }
        guard let bhUID = deviceID(uidContains: "BlackHole").flatMap({ uid($0) }) else { return fail() }
        let devices = includedOutputDevices()
        guard !devices.isEmpty else { return fail() }

        deviceOrder = devices.map(\.uid)
        channelCounts = Dictionary(uniqueKeysWithValues: devices.map { ($0.uid, $0.channels) })

        // A public aggregate survives a crashed owner; a leftover with our
        // UID must go before a new one can take its place.
        if let stale = deviceID(uidContains: Self.aggregateUID) {
            AudioHardwareDestroyAggregateDevice(stale)
        }

        // Aggregate: BlackHole first (clock master, loopback input), then
        // all included outputs with drift compensation. Public, so it shows
        // up in the sound settings and Audio MIDI Setup under our name.
        var subs: [[String: Any]] = [[kAudioSubDeviceUIDKey as String: bhUID]]
        for d in devices {
            subs.append([kAudioSubDeviceUIDKey as String: d.uid,
                         kAudioSubDeviceDriftCompensationKey as String: 1])
        }
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Unison Spatial",
            kAudioAggregateDeviceUIDKey as String: Self.aggregateUID,
            kAudioAggregateDeviceSubDeviceListKey as String: subs,
            kAudioAggregateDeviceMainSubDeviceKey as String: bhUID,
            kAudioAggregateDeviceIsPrivateKey as String: 0,
            kAudioAggregateDeviceIsStackedKey as String: 0
        ]
        var aggID = AudioDeviceID(0)
        guard AudioHardwareCreateAggregateDevice(desc as CFDictionary, &aggID) == noErr else { return fail() }
        aggregateID = aggID
        usleep(150_000)  // aggregate needs a moment to publish streams

        guard setupUnit(aggregate: aggID) else {
            AudioHardwareDestroyAggregateDevice(aggID)
            aggregateID = 0
            return fail()
        }

        updatePositions(positions)

        // Route the system to our aggregate. System stereo lands on its
        // first two channels, which are the loopback. Remember the way
        // back only when leaving a real device, so restarts cannot save
        // the loopback as the place to return to.
        if let currentUID = uid(systemDefaultOutput()),
           !currentUID.contains("BlackHole"), currentUID != Self.aggregateUID {
            UserDefaults.standard.set(currentUID, forKey: Self.prevOutputKey)
        }
        setSystemDefaultOutput(aggID)
        isRunning = true
        pinDefaultOutput()
        NSLog("Unison: spatial engine started, \(devices.count) devices")
        return true
    }

    func stop() {
        teardown()
        if isRunning {
            restorePreviousOutput()
            isRunning = false
            NSLog("Unison: spatial engine stopped")
        }
    }

    // The OS restores the last user-chosen output a few seconds after a
    // new device appears; while spatial runs the aggregate must stay the
    // default or audio silently bypasses the engine.
    private func pinDefaultOutput() {
        var addr = Self.defaultOutputAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning,
                      self.systemDefaultOutput() != self.aggregateID else { return }
                NSLog("Unison: default output moved away, re-pinning aggregate")
                self.setSystemDefaultOutput(self.aggregateID)
            }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
        pinBlock = block
    }

    private func unpinDefaultOutput() {
        guard let block = pinBlock else { return }
        var addr = Self.defaultOutputAddress
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
        pinBlock = nil
    }

    private static let defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    private func teardown() {
        unpinDefaultOutput()
        if let unit = state.unit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            state.unit = nil
        }
        if aggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = 0
        }
    }

    // Crash safety: if a previous run left the system on the loopback or
    // on our aggregate, put it back even though no engine is running.
    func restoreIfStranded() {
        guard !isRunning else { return }
        let currentUID = uid(systemDefaultOutput())
        if let stale = deviceID(uidContains: Self.aggregateUID) {
            AudioHardwareDestroyAggregateDevice(stale)
        }
        guard UserDefaults.standard.string(forKey: Self.prevOutputKey) != nil else { return }
        if let currentUID, currentUID.contains("BlackHole") || currentUID == Self.aggregateUID {
            restorePreviousOutput()
            NSLog("Unison: restored output stranded on loopback")
        } else {
            UserDefaults.standard.removeObject(forKey: Self.prevOutputKey)
        }
    }

    func updatePositions(_ positions: [String: Double]) {
        let speakers = availableSpeakers().map { s in
            var m = s
            m.position = positions[s.id] ?? 0.5
            return m
        }
        state.setMatrix(SpatialMix.matrix(speakers: speakers,
                                          deviceOrder: deviceOrder,
                                          channelCounts: channelCounts,
                                          outputOffset: 2))
    }

    // MARK: - CoreAudio plumbing

    private struct OutputDevice {
        let id: AudioDeviceID
        let uid: String
        let name: String
        let channels: Int
    }

    private func realOutputDevices() -> [OutputDevice] {
        let audio = AudioController()
        return audio.outputDevices()
            .filter { !$0.isVirtualOrAggregate && !$0.uid.contains("BlackHole") }
            .compactMap { out in
                let ch = outputChannels(out.id)
                guard ch > 0 else { return nil }
                return OutputDevice(id: out.id, uid: out.uid, name: out.name, channels: ch)
            }
    }

    // Sorted by UID: CoreAudio enumeration order shuffles when unrelated
    // devices come and go, and a shuffle must not look like a hot-plug.
    private func includedOutputDevices() -> [OutputDevice] {
        realOutputDevices().filter { !excluded.contains($0.uid) }
            .sorted { $0.uid < $1.uid }
    }

    private func setupUnit(aggregate: AudioDeviceID) -> Bool {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else { return false }
        var unitOpt: AudioUnit?
        guard AudioComponentInstanceNew(comp, &unitOpt) == noErr, let unit = unitOpt else { return false }

        var one: UInt32 = 1
        guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO,
                                   kAudioUnitScope_Input, 1, &one, 4) == noErr else { return false }
        var dev = aggregate
        guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                   kAudioUnitScope_Global, 0, &dev, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr
        else { return false }

        let totalOut = outputChannels(aggregate)
        state.totalOutputChannels = totalOut

        var rate = Float64(48000)
        var ra = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var rsize = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(aggregate, &ra, 0, nil, &rsize, &rate)

        func format(_ channels: UInt32) -> AudioStreamBasicDescription {
            AudioStreamBasicDescription(
                mSampleRate: rate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
                mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0)
        }
        var inFmt = format(2)
        guard AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Output, 1, &inFmt,
                                   UInt32(MemoryLayout<AudioStreamBasicDescription>.size)) == noErr else { return false }
        var outFmt = format(UInt32(totalOut))
        guard AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Input, 0, &outFmt,
                                   UInt32(MemoryLayout<AudioStreamBasicDescription>.size)) == noErr else { return false }

        // Reusable non-interleaved input buffers for the callback.
        let abl = AudioBufferList.allocate(maximumBuffers: 2)
        for i in 0..<2 {
            let bytes = state.maxFrames * MemoryLayout<Float32>.size
            abl[i] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(bytes),
                                 mData: malloc(bytes))
        }
        state.inputABL = abl

        var callback = AURenderCallbackStruct(
            inputProc: spatialRender,
            inputProcRefCon: Unmanaged.passUnretained(state).toOpaque())
        guard AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback,
                                   kAudioUnitScope_Input, 0, &callback,
                                   UInt32(MemoryLayout<AURenderCallbackStruct>.size)) == noErr else { return false }

        state.unit = unit
        guard AudioUnitInitialize(unit) == noErr else { return false }
        guard AudioOutputUnitStart(unit) == noErr else { return false }
        return true
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

    private func systemDefaultOutput() -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private func setSystemDefaultOutput(_ id: AudioDeviceID) {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v = id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &v)
    }

    private func restorePreviousOutput() {
        defer { UserDefaults.standard.removeObject(forKey: Self.prevOutputKey) }
        guard let prevUID = UserDefaults.standard.string(forKey: Self.prevOutputKey),
              let id = deviceID(uidContains: prevUID) else { return }
        setSystemDefaultOutput(id)
    }
}
