import SwiftUI

@main
struct UnisonApp: App {
    @StateObject private var state: AppState
    @StateObject private var settings: Settings
    private let keyboard = KeyboardTap()

    init() {
        let built = DeviceDiscovery.buildInitialState()
        let s = AppState(applier: built.applier)
        s.speakers = built.speakers
        s.displays = built.displays
        s.applyAll()  // hardware matches stored levels on launch
        _state = StateObject(wrappedValue: s)
        let cfg = Settings()
        _settings = StateObject(wrappedValue: cfg)
        s.isEnabled = { [weak cfg] id in cfg?.isEnabled(id) ?? true }
        s.volumeScale = { [weak cfg] id in cfg?.volumeScales[id] ?? 1 }
        s.brightnessScale = { [weak cfg] id in cfg?.brightnessScales[id] ?? 1 }
        startKeyboard(s, cfg)
    }

    private func startKeyboard(_ state: AppState, _ settings: Settings) {
        let granted = KeyboardTap.accessibilityGranted(prompt: true)
        NSLog("Unison: accessibility granted: \(granted)")
        keyboard.onKey = { key in
            let step = settings.stepSize
            switch key {
            case .volumeUp, .volumeDown:
                let delta = key == .volumeUp ? step : -step
                let shown: Double
                if settings.keyboardTarget == "all" {
                    state.nudgeAllVolume(delta)
                    shown = state.speakers.first?.volume ?? 0
                } else if let s = state.speakers.first(where: { $0.id == settings.keyboardTarget }) {
                    let v = LevelMath.step(s.volume, by: delta)
                    state.setVolume(id: s.id, v)
                    shown = v
                } else {
                    state.nudgeAllVolume(delta)
                    shown = state.speakers.first?.volume ?? 0
                }
                if settings.hudVolume { HUDOverlay.show(.volume, value: shown) }
            case .mute:
                state.toggleMuteAll()
                let muted = state.speakers.allSatisfy(\.muted)
                if settings.hudVolume {
                    HUDOverlay.show(.mute, value: muted ? 0 : state.speakers.first?.volume ?? 0)
                }
            case .brightnessUp, .brightnessDown:
                let delta = key == .brightnessUp ? step : -step
                let shown: Double
                if settings.keyboardBrightnessTarget == "all" {
                    state.nudgeAllBrightness(delta)
                    shown = state.displays.first?.brightness ?? 0
                } else if let d = state.displays.first(where: { $0.id == settings.keyboardBrightnessTarget }) {
                    let v = LevelMath.step(d.brightness, by: delta)
                    state.setBrightness(id: d.id, v)
                    shown = v
                } else {
                    state.nudgeAllBrightness(delta)
                    shown = state.displays.first?.brightness ?? 0
                }
                if settings.hudBrightness { HUDOverlay.show(.brightness, value: shown) }
            }
        }
        let started = keyboard.start()
        NSLog("Unison: event tap started: \(started)")
    }

    var body: some Scene {
        MenuBarExtra("Unison", systemImage: "slider.horizontal.3",
                     isInserted: $settings.menuIconVisible) {
            PopoverView(state: state, settings: settings)
        }
        .menuBarExtraStyle(.window)

        SwiftUI.Settings {
            SettingsView(settings: settings, state: state)
        }
    }
}
