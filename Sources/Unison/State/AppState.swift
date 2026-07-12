import Foundation
import SwiftUI

protocol DeviceApplier {
    func applyVolume(_ device: SpeakerDevice)
    func applyMute(_ device: SpeakerDevice)
    func applyBrightness(_ device: DisplayDevice)
}

struct NullApplier: DeviceApplier {
    func applyVolume(_ device: SpeakerDevice) {}
    func applyMute(_ device: SpeakerDevice) {}
    func applyBrightness(_ device: DisplayDevice) {}
}

@MainActor
final class AppState: ObservableObject {
    @Published var speakers: [SpeakerDevice] = []
    @Published var displays: [DisplayDevice] = []

    private var applier: DeviceApplier

    init(applier: DeviceApplier) { self.applier = applier }

    // Re-discovers hardware; replaces the applier so stale DDC refs are dropped.
    func refreshDevices() {
        let built = DeviceDiscovery.buildInitialState()
        applier = built.applier
        speakers = built.speakers
        displays = built.displays
        applyAll()
    }

    // Sliders: absolute set.
    func setAllVolume(_ v: Double) {
        let c = LevelMath.clamp(v)
        for i in speakers.indices { speakers[i].volume = c; applier.applyVolume(speakers[i]) }
        persist()
    }
    func setAllBrightness(_ v: Double) {
        let c = LevelMath.clamp(v)
        for i in displays.indices { displays[i].brightness = c; applier.applyBrightness(displays[i]) }
        persist()
    }
    func setVolume(id: String, _ v: Double) {
        guard let i = speakers.firstIndex(where: { $0.id == id }) else { return }
        speakers[i].volume = LevelMath.clamp(v); applier.applyVolume(speakers[i])
        persist()
    }
    func setBrightness(id: String, _ v: Double) {
        guard let i = displays.firstIndex(where: { $0.id == id }) else { return }
        displays[i].brightness = LevelMath.clamp(v); applier.applyBrightness(displays[i])
        persist()
    }

    // Keyboard: relative nudge to all, preserving balance.
    func nudgeAllVolume(_ delta: Double) {
        for i in speakers.indices {
            speakers[i].volume = LevelMath.step(speakers[i].volume, by: delta)
            applier.applyVolume(speakers[i])
        }
        persist()
    }
    func nudgeAllBrightness(_ delta: Double) {
        for i in displays.indices {
            displays[i].brightness = LevelMath.step(displays[i].brightness, by: delta)
            applier.applyBrightness(displays[i])
        }
        persist()
    }

    func toggleMuteAll() {
        let anyUnmuted = speakers.contains { !$0.muted }
        for i in speakers.indices { speakers[i].muted = anyUnmuted; applier.applyMute(speakers[i]) }
        persist()
    }

    func persist() { Persistence.saveVolumes(speakers, brightness: displays) }

    func applyAll() {
        for s in speakers { applier.applyVolume(s) }
        for d in displays { applier.applyBrightness(d) }
    }
}
