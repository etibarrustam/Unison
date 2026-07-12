import CoreAudio

enum VolumeBackend {
    case coreAudio(AudioDeviceID)
    case ddc(String)   // DDCDisplay.id
}

// Physical placement for stereo: a left speaker plays only left-channel
// content, center plays both.
enum SpeakerPosition: String {
    case left, center, right
}

struct SpeakerDevice: Identifiable {
    let id: String
    var name: String
    var backend: VolumeBackend
    var volume: Double
    var muted: Bool
    // Whether the backend can pan; decided at discovery.
    var pannable: Bool = false
    // Effective position for this write; set by AppState at apply time.
    var position: SpeakerPosition = .center
}
