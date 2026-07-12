import Foundation

// Writes already-shaped values to hardware. Mute and scale shaping happen
// in AppState; device.volume/brightness arrive here as final output levels.
struct HardwareApplier: DeviceApplier {
    let audio: AudioController
    let ddc: DDCController
    let builtin: BuiltinDisplayController
    let ddcDisplays: [String: DDCDisplay]   // keyed by DDCDisplay.id
    let ddcBalanceMax: [String: Int]        // DDC displays with audio balance

    func applyVolume(_ device: SpeakerDevice) {
        switch device.backend {
        case .coreAudio(let id):
            audio.setVolume(id, device.volume, position: device.position)
        case .ddc(let key):
            guard let d = ddcDisplays[key] else { return }
            ddc.setVolume(d, percent: Int((device.volume * 100).rounded()))
            if let max = ddcBalanceMax[key] {
                ddc.setBalance(d, position: device.position, max: max)
            }
        }
    }
    func applyMute(_ device: SpeakerDevice) {
        switch device.backend {
        case .coreAudio(let id): audio.setMuted(id, device.muted)
        case .ddc: break  // no reliable DDC mute; the volume write covers it
        }
    }
    func applyBrightness(_ device: DisplayDevice) {
        switch device.backend {
        case .builtin: builtin.setBrightness(device.brightness)
        case .ddc(let key):
            guard let d = ddcDisplays[key] else { return }
            ddc.setBrightness(d, percent: Int((device.brightness * 100).rounded()))
        }
    }
}
