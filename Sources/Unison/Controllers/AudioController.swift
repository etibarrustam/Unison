import Foundation
import CoreAudio

struct AudioOutput: Identifiable {
    let id: AudioDeviceID
    let uid: String            // stable across reboots and replugs
    let name: String
    let supportsSoftwareVolume: Bool
    let isVirtualOrAggregate: Bool
}

final class AudioController {
    var onChange: (() -> Void)?

    func outputDevices() -> [AudioOutput] {
        deviceIDs().compactMap { id in
            guard channelCount(id, scope: kAudioDevicePropertyScopeOutput) > 0 else { return nil }
            let t = transportType(id)
            let virtualOrAggregate = t == kAudioDeviceTransportTypeVirtual
                || t == kAudioDeviceTransportTypeAggregate
                || t == kAudioDeviceTransportTypeAutoAggregate
            return AudioOutput(id: id, uid: uid(id), name: name(id),
                               supportsSoftwareVolume: hasSettableVolume(id),
                               isVirtualOrAggregate: virtualOrAggregate)
        }
    }

    func setVolume(_ id: AudioDeviceID, _ value: Double) {
        var v = Float32(min(1, max(0, value)))
        // Try master, then per-channel 1 and 2.
        if setScalar(id, element: kAudioObjectPropertyElementMain, &v) { return }
        for ch: UInt32 in 1...2 { _ = setScalar(id, element: ch, &v) }
    }

    func setMuted(_ id: AudioDeviceID, _ muted: Bool) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = muted ? 1 : 0
        _ = AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    // MARK: - Private CoreAudio helpers

    private func deviceIDs() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids
    }

    private func uid(_ id: AudioDeviceID) -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var cf: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cf)
        guard status == noErr, let cf else { return "dev-\(id)" }
        return cf.takeRetainedValue() as String
    }

    private func transportType(_ id: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var t: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &t)
        return t
    }

    private func name(_ id: AudioDeviceID) -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var cf: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cf)
        guard status == noErr, let cf else { return "Unknown" }
        return cf.takeRetainedValue() as String
    }

    private func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size)
        guard size > 0 else { return 0 }
        let bl = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { bl.deallocate() }
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, bl)
        let abl = bl.assumingMemoryBound(to: AudioBufferList.self)
        let list = UnsafeMutableAudioBufferListPointer(abl)
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func hasSettableVolume(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(id, &addr) { return true }
        addr.mElement = 1
        return AudioObjectHasProperty(id, &addr)
    }

    private func setScalar(_ id: AudioDeviceID, element: AudioObjectPropertyElement, _ v: inout Float32) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element)
        guard AudioObjectHasProperty(id, &addr) else { return false }
        var settable: DarwinBoolean = false
        AudioObjectIsPropertySettable(id, &addr, &settable)
        guard settable.boolValue else { return false }
        return AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }
}
