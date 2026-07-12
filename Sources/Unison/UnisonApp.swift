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
        s.volumeTrim = { [weak cfg] id in cfg?.volumeTrims[id] ?? 0 }
        s.brightnessTrim = { [weak cfg] id in cfg?.brightnessTrims[id] ?? 0 }
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
            case .brightnessUp:
                state.nudgeAllBrightness(step)
                if settings.hudBrightness {
                    HUDOverlay.show(.brightness, value: state.displays.first?.brightness ?? 0)
                }
            case .brightnessDown:
                state.nudgeAllBrightness(-step)
                if settings.hudBrightness {
                    HUDOverlay.show(.brightness, value: state.displays.first?.brightness ?? 0)
                }
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
