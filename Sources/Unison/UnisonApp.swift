import SwiftUI

@main
struct UnisonApp: App {
    @StateObject private var state: AppState

    init() {
        let built = DeviceDiscovery.buildInitialState()
        let s = AppState(applier: built.applier)
        s.speakers = built.speakers
        s.displays = built.displays
        _state = StateObject(wrappedValue: s)
    }

    var body: some Scene {
        MenuBarExtra("Unison", systemImage: "slider.horizontal.3") {
            PopoverView(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}
