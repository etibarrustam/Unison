import Foundation

struct HardwareApplier: DeviceApplier {
    let audio: AudioController
    let ddc: DDCController
    let builtin: BuiltinDisplayController
    let ddcDisplays: [String: DDCDisplay]   // keyed by DDCDisplay.id

    func applyVolume(_ device: SpeakerDevice) {
        switch device.backend {
        case .coreAudio(let id): audio.setVolume(id, device.muted ? 0 : device.volume)
        case .ddc(let key):
            guard let d = ddcDisplays[key] else { return }
            ddc.setVolume(d, percent: Int((device.muted ? 0 : device.volume) * 100))
        }
    }
    func applyMute(_ device: SpeakerDevice) {
        switch device.backend {
        case .coreAudio(let id): audio.setMuted(id, device.muted)
        case .ddc(let key):
            guard let d = ddcDisplays[key] else { return }
            ddc.setVolume(d, percent: device.muted ? 0 : Int(device.volume * 100))
        }
    }
    func applyBrightness(_ device: DisplayDevice) {
        switch device.backend {
        case .builtin: builtin.setBrightness(device.brightness)
        case .ddc(let key):
            guard let d = ddcDisplays[key] else { return }
            ddc.setBrightness(d, percent: Int(device.brightness * 100))
        }
    }
}
