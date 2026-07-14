import Foundation
import SwiftUI

@MainActor
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
    // Non-nil while the Sound list points at a single real device: only
    // that speaker is controlled, the popover dims the rest. nil means
    // audio flows through the Unison device to every speaker.
    @Published var soloSpeakerID: String?

    private var applier: DeviceApplier
    private var persistWork: DispatchWorkItem?

    // Group operations skip devices for which this returns false.
    var isEnabled: (String) -> Bool = { _ in true }

    // Per-device output scale: hardware = level * scale, so zero stays
    // zero and a scaled device tracks proportionally below the others.
    var volumeScale: (String) -> Double = { _ in 1 }
    var brightnessScale: (String) -> Double = { _ in 1 }

    // Stereo placement, injected from Settings. Pan is 0 left...1 right.
    var spatialEnabled: () -> Bool = { false }
    var speakerPan: (String) -> Double = { _ in 0.5 }

    init(applier: DeviceApplier) { self.applier = applier }

    // The single place a speaker's hardware output is computed: mute and
    // scale both live here so every path agrees.
    private func effectiveVolume(_ s: SpeakerDevice) -> Double {
        s.muted ? 0 : LevelMath.clamp(s.volume * volumeScale(s.id))
    }

    private func apply(_ s: SpeakerDevice) {
        var t = s
        t.volume = effectiveVolume(s)
        t.pan = spatialEnabled() ? LevelMath.clamp(speakerPan(s.id)) : 0.5
        applier.applyVolume(t)
    }
    private func apply(_ d: DisplayDevice) {
        var t = d
        t.brightness = LevelMath.clamp(d.brightness * brightnessScale(d.id))
        applier.applyBrightness(t)
    }

    func reapplyVolume(id: String) {
        if let s = speakers.first(where: { $0.id == id }) { apply(s) }
    }
    func reapplyBrightness(id: String) {
        if let d = displays.first(where: { $0.id == id }) { apply(d) }
    }

    var enabledSpeakersMuted: Bool {
        let enabled = speakers.filter { isEnabled($0.id) }
        return !enabled.isEmpty && enabled.allSatisfy(\.muted)
    }

    // Re-discovers hardware; replaces the applier so stale DDC refs are
    // dropped, but keeps current levels and mute for surviving devices.
    func refreshDevices() {
        let built = DeviceDiscovery.buildInitialState()
        applier = built.applier
        speakers = Self.mergeSpeakers(current: speakers, discovered: built.speakers)
        displays = Self.mergeDisplays(current: displays, discovered: built.displays)
        applyAll()
    }

    static func mergeSpeakers(current: [SpeakerDevice], discovered: [SpeakerDevice]) -> [SpeakerDevice] {
        discovered.map { d in
            guard let old = current.first(where: { $0.id == d.id }) else { return d }
            var m = d
            m.volume = old.volume
            m.muted = old.muted
            return m
        }
    }
    static func mergeDisplays(current: [DisplayDevice], discovered: [DisplayDevice]) -> [DisplayDevice] {
        discovered.map { d in
            guard let old = current.first(where: { $0.id == d.id }) else { return d }
            var m = d
            m.brightness = old.brightness
            return m
        }
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
        let anyUnmuted = speakers.contains { isEnabled($0.id) && !$0.muted }
        for i in speakers.indices where isEnabled(speakers[i].id) {
            speakers[i].muted = anyUnmuted
            // Mute bit for backends that have one, then the volume write:
            // 0 when muting, the restored effective level when unmuting.
            applier.applyMute(speakers[i])
            apply(speakers[i])
        }
        persist()
    }

    // Debounced: slider drags call this on every tick.
    func persist() {
        persistWork?.cancel()
        let speakers = self.speakers
        let displays = self.displays
        let work = DispatchWorkItem { Persistence.saveVolumes(speakers, brightness: displays) }
        persistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func applyAll() {
        for s in speakers { apply(s) }
        for d in displays { apply(d) }
    }
}
