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

    // Per-device scales shape the hardware value, not the shown level.
    // hardware = level * scale: zero stays zero for everyone, and at full
    // level a scaled-down device tops out at its scale.
    @Test func scalesApplyProportionally() {
        let rec = RecordingApplier()
        let s = AppState(applier: rec)
        s.speakers = [
            SpeakerDevice(id: "mac", name: "Mac", backend: .coreAudio(0), volume: 0.4, muted: false),
            SpeakerDevice(id: "lg", name: "LG", backend: .ddc("ext-1"), volume: 0.4, muted: false)
        ]
        s.displays = [
            DisplayDevice(id: "builtin", name: "Built-in", backend: .builtin, brightness: 0.5)
        ]
        s.volumeScale = { $0 == "lg" ? 0.8 : 1.0 }
        s.brightnessScale = { _ in 0.6 }

        s.setAllVolume(0.5)
        #expect(s.speakers.map(\.volume) == [0.5, 0.5])
        #expect(abs((rec.volumes["mac"] ?? 0) - 0.5) < 0.0001)
        #expect(abs((rec.volumes["lg"] ?? 0) - 0.4) < 0.0001)

        s.setAllVolume(0)
        #expect(rec.volumes["mac"] == 0.0)
        #expect(rec.volumes["lg"] == 0.0)

        s.setAllVolume(1.0)
        #expect(rec.volumes["mac"] == 1.0)
        #expect(abs((rec.volumes["lg"] ?? 0) - 0.8) < 0.0001)

        s.setAllBrightness(0.5)
        #expect(s.displays[0].brightness == 0.5)
        #expect(abs((rec.brightnesses["builtin"] ?? 0) - 0.3) < 0.0001)
    }
}

final class RecordingApplier: DeviceApplier {
    var volumes: [String: Double] = [:]
    var brightnesses: [String: Double] = [:]
    var mutes: [String: Bool] = [:]
    var pans: [String: Double] = [:]
    func applyVolume(_ device: SpeakerDevice) {
        volumes[device.id] = device.volume
        pans[device.id] = device.pan
    }
    func applyMute(_ device: SpeakerDevice) { mutes[device.id] = device.muted }
    func applyBrightness(_ device: DisplayDevice) { brightnesses[device.id] = device.brightness }
}

@MainActor
struct MuteAndRefreshTests {
    private func makeScaled() -> (AppState, RecordingApplier) {
        let rec = RecordingApplier()
        let s = AppState(applier: rec)
        s.speakers = [
            SpeakerDevice(id: "mac", name: "Mac", backend: .coreAudio(0), volume: 0.4, muted: false),
            SpeakerDevice(id: "lg", name: "LG", backend: .ddc("ext-1"), volume: 0.4, muted: false)
        ]
        s.volumeScale = { $0 == "lg" ? 0.8 : 1.0 }
        return (s, rec)
    }

    // Mute writes 0; volume changes while muted stay silent; unmute
    // restores the scaled level instead of leaving hardware at 0.
    @Test func unmuteRestoresScaledVolume() {
        let (s, rec) = makeScaled()
        s.toggleMuteAll()
        #expect(rec.volumes["mac"] == 0.0)
        #expect(rec.mutes["mac"] == true)

        s.nudgeAllVolume(0.1)
        #expect(rec.volumes["mac"] == 0.0)
        #expect(rec.volumes["lg"] == 0.0)

        s.toggleMuteAll()
        #expect(rec.mutes["mac"] == false)
        #expect(abs((rec.volumes["mac"] ?? 0) - 0.5) < 0.0001)
        #expect(abs((rec.volumes["lg"] ?? 0) - 0.4) < 0.0001)
    }

    // Device refresh must not discard current levels or mute state for
    // devices that are still present.
    @Test func mergePreservesExistingState() {
        let current = [
            SpeakerDevice(id: "a", name: "A", backend: .coreAudio(1), volume: 0.7, muted: true),
            SpeakerDevice(id: "gone", name: "Gone", backend: .coreAudio(2), volume: 0.5, muted: false)
        ]
        let discovered = [
            SpeakerDevice(id: "a", name: "A", backend: .coreAudio(9), volume: 0.3, muted: false),
            SpeakerDevice(id: "new", name: "New", backend: .coreAudio(3), volume: 0.3, muted: false)
        ]
        let merged = AppState.mergeSpeakers(current: current, discovered: discovered)
        #expect(merged.count == 2)
        #expect(merged[0].volume == 0.7)
        #expect(merged[0].muted == true)
        if case .coreAudio(let id) = merged[0].backend { #expect(id == 9) } else { Issue.record("backend not updated") }
        #expect(merged[1].id == "new")
        #expect(merged[1].volume == 0.3)
    }

    @Test func mergePreservesDisplayBrightness() {
        let current = [DisplayDevice(id: "d", name: "D", backend: .builtin, brightness: 0.9)]
        let discovered = [DisplayDevice(id: "d", name: "D", backend: .builtin, brightness: 0.7)]
        let merged = AppState.mergeDisplays(current: current, discovered: discovered)
        #expect(merged[0].brightness == 0.9)
    }

    // Speaker positions reach the applier only while placement is on.
    @Test func positionsApplyOnlyWhenSpatialEnabled() {
        let (s, rec) = makeScaled()
        s.speakerPan = { $0 == "mac" ? 0.9 : 0.1 }

        s.spatialEnabled = { false }
        s.setAllVolume(0.5)
        #expect(rec.pans["mac"] == 0.5)
        #expect(rec.pans["lg"] == 0.5)

        s.spatialEnabled = { true }
        s.setAllVolume(0.5)
        #expect(rec.pans["mac"] == 0.9)
        #expect(rec.pans["lg"] == 0.1)
    }

    // HUD mute state must consider enabled speakers only.
    @Test func muteStateIgnoresDisabledSpeakers() {
        let (s, _) = makeScaled()
        s.isEnabled = { $0 != "lg" }
        s.toggleMuteAll()
        #expect(s.enabledSpeakersMuted == true)
        s.toggleMuteAll()
        #expect(s.enabledSpeakersMuted == false)
    }
}
