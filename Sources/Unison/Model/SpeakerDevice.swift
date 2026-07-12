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
    // Whether the backend can pan; decided at discovery.
    var pannable: Bool = false
    // Stereo position for this write, 0 left...1 right; set by AppState
    // at apply time.
    var pan: Double = 0.5
}
