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

    // Group operations skip devices for which this returns false.
    var isEnabled: (String) -> Bool = { _ in true }

    // Per-device output scale: hardware = level * scale, so zero stays
    // zero and a scaled device tracks proportionally below the others.
    var volumeScale: (String) -> Double = { _ in 1 }
    var brightnessScale: (String) -> Double = { _ in 1 }

    init(applier: DeviceApplier) { self.applier = applier }

    // All hardware writes pass through here so scales always apply.
    private func apply(_ s: SpeakerDevice) {
        var t = s
        t.volume = LevelMath.clamp(s.volume * volumeScale(s.id))
        applier.applyVolume(t)
    }
    private func apply(_ d: DisplayDevice) {
        var t = d
        t.brightness = LevelMath.clamp(d.brightness * brightnessScale(d.id))
        applier.applyBrightness(t)
    }
    private func applyMute(_ s: SpeakerDevice) {
        var t = s
        t.volume = LevelMath.clamp(s.volume * volumeScale(s.id))
        applier.applyMute(t)
    }

    func reapplyVolume(id: String) {
        if let s = speakers.first(where: { $0.id == id }) { apply(s) }
    }
    func reapplyBrightness(id: String) {
        if let d = displays.first(where: { $0.id == id }) { apply(d) }
    }

    // Re-discovers hardware; replaces the applier so stale DDC refs are dropped.
    func refreshDevices() {
        let built = DeviceDiscovery.buildInitialState()
        applier = built.applier
        speakers = built.speakers
        displays = built.displays
        applyAll()
    }

    // Equalize: absolute set for every enabled device.
    func setAllVolume(_ v: Double) {
        let c = LevelMath.clamp(v)
        for i in speakers.indices where isEnabled(speakers[i].id) {
            speakers[i].volume = c; apply(speakers[i])
        }
        persist()
    }
    func setAllBrightness(_ v: Double) {
        let c = LevelMath.clamp(v)
        for i in displays.indices where isEnabled(displays[i].id) {
            displays[i].brightness = c; apply(displays[i])
        }
        persist()
    }
    func setVolume(id: String, _ v: Double) {
        guard let i = speakers.firstIndex(where: { $0.id == id }) else { return }
        speakers[i].volume = LevelMath.clamp(v); apply(speakers[i])
        persist()
    }
    func setBrightness(id: String, _ v: Double) {
        guard let i = displays.firstIndex(where: { $0.id == id }) else { return }
        displays[i].brightness = LevelMath.clamp(v); apply(displays[i])
        persist()
    }

    // Keyboard and All sliders: relative nudge, preserving balance.
    func nudgeAllVolume(_ delta: Double) {
        for i in speakers.indices where isEnabled(speakers[i].id) {
            speakers[i].volume = LevelMath.step(speakers[i].volume, by: delta)
            apply(speakers[i])
        }
        persist()
    }
    func nudgeAllBrightness(_ delta: Double) {
        for i in displays.indices where isEnabled(displays[i].id) {
            displays[i].brightness = LevelMath.step(displays[i].brightness, by: delta)
            apply(displays[i])
        }
        persist()
    }

    func toggleMuteAll() {
        let enabled = speakers.filter { isEnabled($0.id) }
        let anyUnmuted = enabled.contains { !$0.muted }
        for i in speakers.indices where isEnabled(speakers[i].id) {
            speakers[i].muted = anyUnmuted; applyMute(speakers[i])
        }
        persist()
    }

    func persist() { Persistence.saveVolumes(speakers, brightness: displays) }

    func applyAll() {
        for s in speakers { apply(s) }
        for d in displays { apply(d) }
    }
}
