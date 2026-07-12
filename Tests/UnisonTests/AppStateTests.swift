import Testing
@testable import Unison

@MainActor
struct AppStateTests {
    private func makeState() -> AppState {
        let s = AppState(applier: NullApplier())
        s.speakers = [
            SpeakerDevice(id: "mac", name: "Mac", backend: .coreAudio(0), volume: 0.4, muted: false),
            SpeakerDevice(id: "lg", name: "LG", backend: .ddc("ext-1"), volume: 0.6, muted: false)
        ]
        s.displays = [
            DisplayDevice(id: "builtin", name: "Built-in", backend: .builtin, brightness: 0.5),
            DisplayDevice(id: "lg", name: "LG", backend: .ddc("ext-1"), brightness: 0.8)
        ]
        return s
    }

    // "All" slider sets everyone to the same absolute value.
    @Test func setAllVolumeAbsolute() {
        let s = makeState()
        s.setAllVolume(0.25)
        #expect(s.speakers.map(\.volume) == [0.25, 0.25])
    }

    // Keyboard nudge applies the same delta to all, preserving balance and clamping.
    @Test func nudgeAllVolumeRelative() {
        let s = makeState()
        s.nudgeAllVolume(0.1)
        #expect(abs(s.speakers[0].volume - 0.5) < 0.0001)
        #expect(abs(s.speakers[1].volume - 0.7) < 0.0001)
    }

    @Test func setSingleDeviceOnly() {
        let s = makeState()
        s.setVolume(id: "mac", 0.9)
        #expect(s.speakers[0].volume == 0.9)
        #expect(s.speakers[1].volume == 0.6)
    }

    // Disabled devices are skipped by group operations.
    @Test func disabledDeviceUntouched() {
        let s = makeState()
        s.isEnabled = { $0 != "lg" }
        s.nudgeAllVolume(0.1)
        s.setAllBrightness(0.9)
        #expect(abs(s.speakers[0].volume - 0.5) < 0.0001)
        #expect(s.speakers[1].volume == 0.6)
        #expect(s.displays[0].brightness == 0.9)
        #expect(s.displays[1].brightness == 0.8)
    }

    // Equalize flattens the group to one value.
    @Test func equalizeSetsAllEqual() {
        let s = makeState()
        s.setAllVolume(0.5)
        #expect(s.speakers.map(\.volume) == [0.5, 0.5])
    }
}
