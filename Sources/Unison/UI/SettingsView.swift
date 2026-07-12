import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Show menu bar icon", isOn: $settings.menuIconVisible)
                Text("A hidden icon comes back when Unison is relaunched.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Overlay") {
                Toggle("Show volume overlay", isOn: $settings.hudVolume)
                Toggle("Show brightness overlay", isOn: $settings.hudBrightness)
            }

            Section("Keyboard") {
                Picker("Volume keys control", selection: $settings.keyboardTarget) {
                    Text("All devices").tag("all")
                    ForEach(state.speakers) { Text($0.name).tag($0.id) }
                }
                VStack(alignment: .leading) {
                    Text("Step size: \(Int(settings.stepSize * 100))%")
                    Slider(value: $settings.stepSize, in: 0.02...0.25)
                }
            }

            Section("Speakers") {
                ForEach(state.speakers) { s in
                    Toggle(s.name, isOn: enabledBinding(s.id))
                }
            }

            Section("Displays") {
                ForEach(state.displays) { d in
                    Toggle(d.name, isOn: enabledBinding(d.id))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 480)
    }

    private func enabledBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { settings.isEnabled(id) },
                set: { settings.setEnabled(id, $0) })
    }
}
