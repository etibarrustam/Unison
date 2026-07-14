import Foundation
import AudioToolbox

// Hosts the system AUSpatialMixer for spatial mode: the tap's left and
// right channels become two mono point sources at the classic stereo
// angles, and every included speaker channel becomes one output channel
// declared at its real position. Apple's vector-based panning then
// projects the stereo field onto the actual speaker geometry, which the
// SpatialMixerProbe prototype verified honors custom coordinates.
//
// Built on the main actor, rendered on the HAL IO thread. The render side
// only reads state that never changes after setup, so no lock is needed
// inside a render pass.
final class SpatialMixerRenderer: @unchecked Sendable {
    // One physical speaker channel: where it sits in the aggregate's flat
    // channel numbering, its direction from the listener in degrees
    // (0 front, negative left, positive right, +-180 behind), and its
    // distance in meters. Distance drives alignment delays only; loudness
    // stays under the volume controls.
    struct SpeakerChannel {
        let aggregateChannel: Int
        let azimuth: Float
        var distance: Float = 1
    }

    private static let maxFrames = 4096
    private static let sourceAzimuth: Float = 30  // virtual L/R speakers
    // Ring capacity must cover maxFrames plus the largest alignment delay
    // (a 6 m spread is ~840 samples at 48 kHz). Power of two for masking.
    private static let ringCap = 8192

    private var unit: AudioUnit?
    private let speakers: [SpeakerChannel]
    private var channelForFlatIndex: [Int: Int] = [:]  // aggregate channel -> mixer output channel
    private var scratch: [UnsafeMutablePointer<Float32>] = []
    private var ablMem: UnsafeMutableRawPointer?  // preallocated: no malloc on the IO thread
    private var sampleTime: Double = 0
    // Alignment delay per speaker in samples, with one ring per delayed
    // speaker. Empty when every speaker is equidistant.
    private var delays: [Int] = []
    private var rings: [UnsafeMutablePointer<Float32>] = []
    private var ringPos = 0

    // Input stash: valid only for the duration of one render pass.
    private var inL: UnsafePointer<Float32>?
    private var inR: UnsafePointer<Float32>?
    private var strideL = 1
    private var strideR = 1

    private(set) var ready = false

    // Diagnostics for the hidden debug dump; torn reads are harmless.
    var cbHits = 0
    var cbPeak: Float = 0
    var auPeak: Float = 0
    var mapHits = 0

    // Reads the live parameter state back from the unit.
    func paramDump() -> String {
        guard let unit else { return "no-unit" }
        var out = ""
        for bus: UInt32 in 0...1 {
            var vals: [AudioUnitParameterValue] = []
            for p in [kSpatialMixerParam_Azimuth, kSpatialMixerParam_Distance,
                      kSpatialMixerParam_Gain, kSpatialMixerParam_Enable] {
                var v: AudioUnitParameterValue = -999
                AudioUnitGetParameter(unit, p, kAudioUnitScope_Input, bus, &v)
                vals.append(v)
            }
            out += "bus\(bus)[az=\(vals[0]) d=\(vals[1]) g=\(vals[2]) en=\(vals[3])] "
        }
        return out
    }

    init(speakers: [SpeakerChannel], sampleRate: Double) {
        self.speakers = Self.spreadCoincident(speakers)
        guard !speakers.isEmpty, speakers.count <= 64 else { return }
        for (i, s) in speakers.enumerated() { channelForFlatIndex[s.aggregateChannel] = i }
        scratch = (0..<speakers.count).map { _ in
            let p = UnsafeMutablePointer<Float32>.allocate(capacity: Self.maxFrames)
            p.initialize(repeating: 0, count: Self.maxFrames)
            return p
        }
        ablMem = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<AudioBufferList>.size
                + (speakers.count - 1) * MemoryLayout<AudioBuffer>.stride,
            alignment: 16)
        delays = SpatialMix.delaySamples(distances: self.speakers.map(\.distance),
                                         sampleRate: sampleRate)
            .map { min($0, Self.ringCap - Self.maxFrames - 1) }
        if delays.contains(where: { $0 > 0 }) {
            rings = (0..<speakers.count).map { _ in
                let p = UnsafeMutablePointer<Float32>.allocate(capacity: Self.ringCap)
                p.initialize(repeating: 0, count: Self.ringCap)
                return p
            }
        }
        ready = setup(sampleRate: sampleRate)
        if !ready { NSLog("Unison: spatial mixer setup failed, matrix fallback active") }
    }

    // Vector-based panning cannot solve coincident speakers and renders
    // silence for the whole array. Two speakers at the same position are a
    // legitimate setup (both "full left", one per device), so azimuths are
    // quantized to whole degrees and coincident ones fan out to the
    // nearest free degree, which is physically inaudible.
    static func spreadCoincident(_ speakers: [SpeakerChannel]) -> [SpeakerChannel] {
        var used = Set<Int>()
        return speakers.map { s in
            let base = Int(s.azimuth.rounded())
            var az = base
            var delta = 0
            while used.contains(az) {
                delta = delta >= 0 ? -(delta + 1) : -delta  // -1, +1, -2, +2...
                az = base + delta
            }
            used.insert(az)
            return SpeakerChannel(aggregateChannel: s.aggregateChannel, azimuth: Float(az),
                                  distance: s.distance)
        }
    }

    deinit {
        if let unit {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        for p in scratch { p.deallocate() }
        for p in rings { p.deallocate() }
        ablMem?.deallocate()
    }

    private func setup(sampleRate: Double) -> Bool {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Mixer,
            componentSubType: kAudioUnitSubType_SpatialMixer,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else { return false }
        var unitOpt: AudioUnit?
        guard AudioComponentInstanceNew(comp, &unitOpt) == noErr, let au = unitOpt else { return false }
        unit = au

        var two: UInt32 = 2
        guard AudioUnitSetProperty(au, kAudioUnitProperty_ElementCount,
                                   kAudioUnitScope_Input, 0, &two, 4) == noErr else { return false }

        var mono = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var out = mono
        out.mChannelsPerFrame = UInt32(speakers.count)

        let asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Output, 0, &out, asbdSize) == noErr
        else { return false }

        // Output layout: one speaker per channel at its declared position,
        // one meter away; distance shaping is a later, separate step.
        let count = speakers.count
        let layoutSize = MemoryLayout<AudioChannelLayout>.size
            + (count - 1) * MemoryLayout<AudioChannelDescription>.stride
        let layoutMem = UnsafeMutableRawPointer.allocate(byteCount: layoutSize, alignment: 16)
        defer { layoutMem.deallocate() }
        memset(layoutMem, 0, layoutSize)
        let layout = layoutMem.assumingMemoryBound(to: AudioChannelLayout.self)
        layout.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions
        layout.pointee.mNumberChannelDescriptions = UInt32(count)
        let descs = layoutMem.advanced(by: MemoryLayout<AudioChannelLayout>.offset(of: \.mChannelDescriptions)!)
            .assumingMemoryBound(to: AudioChannelDescription.self)
        for (i, s) in speakers.enumerated() {
            descs[i].mChannelLabel = kAudioChannelLabel_UseCoordinates
            descs[i].mChannelFlags = [.sphericalCoordinates, .meters]
            descs[i].mCoordinates = (s.azimuth, 0, 1)
        }
        guard AudioUnitSetProperty(au, kAudioUnitProperty_AudioChannelLayout,
                                   kAudioUnitScope_Output, 0, layout, UInt32(layoutSize)) == noErr
        else { return false }

        var maxFrames = UInt32(Self.maxFrames)
        _ = AudioUnitSetProperty(au, kAudioUnitProperty_MaximumFramesPerSlice,
                                 kAudioUnitScope_Global, 0, &maxFrames, 4)

        let refCon = Unmanaged.passUnretained(self).toOpaque()
        for bus: UInt32 in 0...1 {
            guard AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat,
                                       kAudioUnitScope_Input, bus, &mono, asbdSize) == noErr
            else { return false }
            var alg = AUSpatializationAlgorithm.spatializationAlgorithm_VectorBasedPanning.rawValue
            guard AudioUnitSetProperty(au, kAudioUnitProperty_SpatializationAlgorithm,
                                       kAudioUnitScope_Input, bus, &alg, 4) == noErr
            else { return false }
            var cb = AURenderCallbackStruct(inputProc: sourceCallback, inputProcRefCon: refCon)
            guard AudioUnitSetProperty(au, kAudioUnitProperty_SetRenderCallback,
                                       kAudioUnitScope_Input, bus, &cb,
                                       UInt32(MemoryLayout<AURenderCallbackStruct>.size)) == noErr
            else { return false }
        }

        guard AudioUnitInitialize(au) == noErr else { return false }
        for bus: UInt32 in 0...1 {
            let az = bus == 0 ? -Self.sourceAzimuth : Self.sourceAzimuth
            AudioUnitSetParameter(au, kSpatialMixerParam_Azimuth, kAudioUnitScope_Input, bus, az, 0)
            AudioUnitSetParameter(au, kSpatialMixerParam_Distance, kAudioUnitScope_Input, bus, 1, 0)
        }
        return true
    }

    // Copies the stashed tap channel for the requested source bus.
    private let sourceCallback: AURenderCallback = { refCon, _, _, bus, frames, ioData in
        let renderer = Unmanaged<SpatialMixerRenderer>.fromOpaque(refCon).takeUnretainedValue()
        guard let abl = ioData else { return noErr }
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        guard let data = buffers[0].mData?.assumingMemoryBound(to: Float32.self) else { return noErr }
        renderer.cbHits += 1
        let src = bus == 0 ? renderer.inL : renderer.inR
        let stride = bus == 0 ? renderer.strideL : renderer.strideR
        guard let src else {
            memset(data, 0, Int(frames) * 4)
            return noErr
        }
        for f in 0..<Int(frames) {
            data[f] = src[f * stride]
            renderer.cbPeak = max(renderer.cbPeak, abs(data[f]))
        }
        return noErr
    }

    // Runs on the HAL IO thread. Renders the two sources onto the speaker
    // channels and writes them into the aggregate's buffers, silencing
    // every unmapped channel. Returns nil if the mixer could not render,
    // so the caller falls back to the gain matrix.
    func render(inL: UnsafePointer<Float32>, strideL: Int,
                inR: UnsafePointer<Float32>, strideR: Int,
                frames: Int,
                output: UnsafeMutableAudioBufferListPointer) -> Float? {
        guard ready, let unit, let ablMem, frames <= Self.maxFrames else { return nil }
        self.inL = inL; self.strideL = strideL
        self.inR = inR; self.strideR = strideR
        defer { self.inL = nil; self.inR = nil }

        var ts = AudioTimeStamp()
        ts.mSampleTime = sampleTime
        ts.mFlags = .sampleTimeValid
        sampleTime += Double(frames)

        let abl = ablMem.assumingMemoryBound(to: AudioBufferList.self)
        abl.pointee.mNumberBuffers = UInt32(speakers.count)
        let bufs = UnsafeMutableAudioBufferListPointer(abl)
        for i in 0..<speakers.count {
            bufs[i] = AudioBuffer(mNumberChannels: 1,
                                  mDataByteSize: UInt32(frames * 4),
                                  mData: UnsafeMutableRawPointer(scratch[i]))
        }
        var flags = AudioUnitRenderActionFlags()
        guard AudioUnitRender(unit, &flags, &ts, 0, UInt32(frames), abl) == noErr else { return nil }
        for s in scratch {
            for f in 0..<frames { auPeak = max(auPeak, abs(s[f])) }
        }

        var peak: Float = 0
        var flatIndex = 0
        for buf in output {
            let ch = max(1, Int(buf.mNumberChannels))
            guard let data = buf.mData?.assumingMemoryBound(to: Float32.self) else {
                flatIndex += ch
                continue
            }
            let bufFrames = Int(buf.mDataByteSize) / (4 * ch)
            let n = min(frames, bufFrames)
            for c in 0..<ch {
                if let s = channelForFlatIndex[flatIndex + c] {
                    mapHits += 1
                    let src = scratch[s]
                    if rings.isEmpty || delays[s] == 0 {
                        for f in 0..<n {
                            let v = src[f]
                            data[f * ch + c] = v
                            peak = max(peak, abs(v))
                        }
                    } else {
                        // Alignment delay: write the fresh samples into the
                        // ring, play the ones from delay samples ago.
                        let ring = rings[s]
                        let mask = Self.ringCap - 1
                        let d = delays[s]
                        for f in 0..<n {
                            ring[(ringPos + f) & mask] = src[f]
                            let v = ring[(ringPos + f - d + Self.ringCap) & mask]
                            data[f * ch + c] = v
                            peak = max(peak, abs(v))
                        }
                    }
                    for f in n..<bufFrames { data[f * ch + c] = 0 }
                } else {
                    for f in 0..<bufFrames { data[f * ch + c] = 0 }
                }
            }
            flatIndex += ch
        }
        if !rings.isEmpty { ringPos = (ringPos + frames) & (Self.ringCap - 1) }
        return peak
    }
}
