// Probe: does AUSpatialMixer honor custom speaker coordinates with
// vector-based panning?
//
// Renders a mono sine source offline through kAudioUnitSubType_SpatialMixer
// while sweeping the source azimuth, and prints per-output-channel RMS for
// three output layouts:
//   A. standard quadraphonic layout tag        (sanity check)
//   B. custom coordinates placed like a quad   (should match A)
//   C. custom lopsided coordinates             (the actual question)
// If C distributes energy differently from B, coordinates are honored and
// Unison can delegate positional math to Apple. If C matches B or the
// layout is rejected, we implement VBAP ourselves.
//
// Build & run:
//   swiftc -O Prototypes/SpatialMixerProbe.swift -o /tmp/spatialprobe \
//     -framework AudioToolbox -framework CoreAudio && /tmp/spatialprobe

import AudioToolbox
import Foundation

let sampleRate = 48000.0
let frameCount: UInt32 = 512
var tonePhase = 0.0

// Mono 440 Hz sine fed to input bus 0.
let toneCallback: AURenderCallback = { _, _, _, _, frames, ioData in
    guard let abl = ioData else { return noErr }
    let buffers = UnsafeMutableAudioBufferListPointer(abl)
    guard let data = buffers[0].mData?.assumingMemoryBound(to: Float32.self) else { return noErr }
    for f in 0..<Int(frames) {
        data[f] = Float32(sin(tonePhase) * 0.5)
        tonePhase += 2.0 * .pi * 440.0 / sampleRate
    }
    return noErr
}

func monoFormat() -> AudioStreamBasicDescription {
    AudioStreamBasicDescription(
        mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
        mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
        mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
}

func outputFormat(channels: UInt32) -> AudioStreamBasicDescription {
    var f = monoFormat()
    f.mChannelsPerFrame = channels
    return f
}

func check(_ status: OSStatus, _ what: String) -> Bool {
    if status != noErr { print("  \(what) failed: \(status)") ; return false }
    return true
}

// Builds the mixer for one layout. azimuths nil selects the plain quad tag;
// otherwise each entry becomes a speaker at that azimuth (degrees, 0 front,
// positive right, 1 m away) via kAudioChannelLabel_UseCoordinates.
func makeMixer(azimuths: [Float]?) -> AudioUnit? {
    var desc = AudioComponentDescription(
        componentType: kAudioUnitType_Mixer,
        componentSubType: kAudioUnitSubType_SpatialMixer,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0, componentFlagsMask: 0)
    guard let comp = AudioComponentFindNext(nil, &desc) else {
        print("  spatial mixer component not found"); return nil
    }
    var unitOpt: AudioUnit?
    guard check(AudioComponentInstanceNew(comp, &unitOpt), "instantiate"),
          let unit = unitOpt else { return nil }

    var one: UInt32 = 1
    _ = AudioUnitSetProperty(unit, kAudioUnitProperty_ElementCount,
                             kAudioUnitScope_Input, 0, &one, 4)

    var inFmt = monoFormat()
    guard check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                                     kAudioUnitScope_Input, 0, &inFmt,
                                     UInt32(MemoryLayout<AudioStreamBasicDescription>.size)),
                "input format") else { return nil }

    var outFmt = outputFormat(channels: 4)
    guard check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                                     kAudioUnitScope_Output, 0, &outFmt,
                                     UInt32(MemoryLayout<AudioStreamBasicDescription>.size)),
                "output format") else { return nil }

    // Output channel layout.
    let descCount = 4
    let layoutSize = MemoryLayout<AudioChannelLayout>.size
        + (descCount - 1) * MemoryLayout<AudioChannelDescription>.stride
    let layoutMem = UnsafeMutableRawPointer.allocate(byteCount: layoutSize, alignment: 16)
    defer { layoutMem.deallocate() }
    memset(layoutMem, 0, layoutSize)
    let layout = layoutMem.assumingMemoryBound(to: AudioChannelLayout.self)

    if let azimuths {
        layout.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions
        layout.pointee.mNumberChannelDescriptions = UInt32(descCount)
        let descs = UnsafeMutableRawPointer(layout).advanced(by: MemoryLayout<AudioChannelLayout>.offset(of: \.mChannelDescriptions)!)
            .assumingMemoryBound(to: AudioChannelDescription.self)
        for (i, az) in azimuths.enumerated() {
            descs[i].mChannelLabel = kAudioChannelLabel_UseCoordinates
            descs[i].mChannelFlags = [.sphericalCoordinates, .meters]
            descs[i].mCoordinates = (az, 0, 1)
        }
    } else {
        layout.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_Quadraphonic
    }
    guard check(AudioUnitSetProperty(unit, kAudioUnitProperty_AudioChannelLayout,
                                     kAudioUnitScope_Output, 0, layout, UInt32(layoutSize)),
                "output layout") else { return nil }

    var alg: UInt32 = AUSpatializationAlgorithm.spatializationAlgorithm_VectorBasedPanning.rawValue
    guard check(AudioUnitSetProperty(unit, kAudioUnitProperty_SpatializationAlgorithm,
                                     kAudioUnitScope_Input, 0, &alg, 4),
                "vector based panning") else { return nil }

    var cb = AURenderCallbackStruct(inputProc: toneCallback, inputProcRefCon: nil)
    guard check(AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback,
                                     kAudioUnitScope_Input, 0, &cb,
                                     UInt32(MemoryLayout<AURenderCallbackStruct>.size)),
                "render callback") else { return nil }

    guard check(AudioUnitInitialize(unit), "initialize") else { return nil }
    return unit
}

func rms(unit: AudioUnit, azimuth: Float) -> [Double]? {
    AudioUnitSetParameter(unit, kSpatialMixerParam_Azimuth, kAudioUnitScope_Input, 0, azimuth, 0)
    AudioUnitSetParameter(unit, kSpatialMixerParam_Distance, kAudioUnitScope_Input, 0, 1, 0)

    let byteCount = Int(frameCount) * 4
    var ablMem = [UInt8](repeating: 0, count: MemoryLayout<AudioBufferList>.size
                         + 3 * MemoryLayout<AudioBuffer>.stride)
    var channelData = (0..<4).map { _ in [Float32](repeating: 0, count: Int(frameCount)) }
    var sums = [Double](repeating: 0, count: 4)
    var counted = 0

    for pull in 0..<24 {
        var ts = AudioTimeStamp()
        ts.mSampleTime = Double(pull) * Double(frameCount)
        ts.mFlags = .sampleTimeValid
        var flags = AudioUnitRenderActionFlags()
        let ok: OSStatus = ablMem.withUnsafeMutableBytes { raw in
            let abl = raw.baseAddress!.assumingMemoryBound(to: AudioBufferList.self)
            abl.pointee.mNumberBuffers = 4
            let bufs = UnsafeMutableAudioBufferListPointer(abl)
            for c in 0..<4 {
                channelData[c].withUnsafeMutableBufferPointer { p in
                    bufs[c] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(byteCount),
                                          mData: UnsafeMutableRawPointer(p.baseAddress))
                }
            }
            return AudioUnitRender(unit, &flags, &ts, 0, frameCount, abl)
        }
        guard ok == noErr else { print("  render failed: \(ok)"); return nil }
        if pull >= 8 {  // skip parameter ramp-in
            for c in 0..<4 {
                sums[c] += channelData[c].reduce(0.0) { $0 + Double($1) * Double($1) }
            }
            counted += 1
        }
    }
    let n = Double(counted) * Double(frameCount)
    return sums.map { ($0 / n).squareRoot() }
}

let sweep: [Float] = [0, -45, 45, -90, 90, -135, 135, 180]

func runCase(_ name: String, azimuths: [Float]?) {
    print("\n=== \(name)")
    guard let unit = makeMixer(azimuths: azimuths) else { return }
    defer { AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit) }
    print(String(format: "%8@ | %8@ %8@ %8@ %8@", "azimuth" as NSString,
                 "ch1" as NSString, "ch2" as NSString, "ch3" as NSString, "ch4" as NSString))
    for az in sweep {
        tonePhase = 0
        guard let levels = rms(unit: unit, azimuth: az) else { return }
        let cells = levels.map { String(format: "%8.4f", $0) }.joined(separator: " ")
        print(String(format: "%8.0f | %@", az, cells))
    }
}

runCase("A: quadraphonic layout tag (sanity)", azimuths: nil)
runCase("B: custom coordinates shaped like a quad (-45, 45, -135, 135)",
        azimuths: [-45, 45, -135, 135])
runCase("C: custom lopsided coordinates (-30, -100, -150, 170)",
        azimuths: [-30, -100, -150, 170])
