import CoreAudio

enum VolumeBackend {
    case coreAudio(AudioDeviceID)
    case ddc(String)   // DDCDisplay.id
}

struct SpeakerDevice: Identifiable {
    let id: String
    var name: String
    var backend: VolumeBackend
    var volume: Double
    var muted: Bool
}
