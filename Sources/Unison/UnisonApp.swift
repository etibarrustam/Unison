import SwiftUI

@main
struct UnisonApp: App {
    var body: some Scene {
        MenuBarExtra("Unison", systemImage: "slider.horizontal.3") {
            Text("Unison is running")
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.window)
    }
}
