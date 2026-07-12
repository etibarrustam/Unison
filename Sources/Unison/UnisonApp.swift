import SwiftUI

@main
struct UnisonApp: App {
    @StateObject private var state: AppState
    private let keyboard = KeyboardTap()

    init() {
        let built = DeviceDiscovery.buildInitialState()
        let s = AppState(applier: built.applier)
        s.speakers = built.speakers
        s.displays = built.displays
        s.applyAll()  // hardware matches stored levels on launch
        _state = StateObject(wrappedValue: s)
        startKeyboard(s)
    }

    private func startKeyboard(_ state: AppState) {
        let granted = KeyboardTap.accessibilityGranted(prompt: true)
        NSLog("Unison: accessibility granted: \(granted)")
        keyboard.onKey = { key in
            let step = 0.0625
            switch key {
            case .volumeUp:
                state.nudgeAllVolume(step)
                HUDOverlay.show(.volume, value: state.speakers.first?.volume ?? 0)
            case .volumeDown:
                state.nudgeAllVolume(-step)
                HUDOverlay.show(.volume, value: state.speakers.first?.volume ?? 0)
            case .mute:
                state.toggleMuteAll()
                let muted = state.speakers.allSatisfy(\.muted)
                HUDOverlay.show(.mute, value: muted ? 0 : state.speakers.first?.volume ?? 0)
            case .brightnessUp:
                state.nudgeAllBrightness(step)
                HUDOverlay.show(.brightness, value: state.displays.first?.brightness ?? 0)
            case .brightnessDown:
                state.nudgeAllBrightness(-step)
                HUDOverlay.show(.brightness, value: state.displays.first?.brightness ?? 0)
            }
        }
        let started = keyboard.start()
        NSLog("Unison: event tap started: \(started)")
    }

    var body: some Scene {
        MenuBarExtra("Unison", systemImage: "slider.horizontal.3") {
            PopoverView(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}
