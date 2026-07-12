import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var state: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Left: app behavior
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("General") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Launch at login", isOn: $settings.launchAtLogin)
                        Toggle("Show menu bar icon", isOn: $settings.menuIconVisible)
                        Text("A hidden icon comes back when Unison is relaunched.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(6)
                }
                GroupBox("Overlay") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Show volume overlay", isOn: $settings.hudVolume)
                        Toggle("Show brightness overlay", isOn: $settings.hudBrightness)
                    }.padding(6)
                }
                GroupBox("Keyboard") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Volume keys control", selection: $settings.keyboardTarget) {
                            Text("All devices").tag("all")
                            ForEach(state.speakers) { Text($0.name).tag($0.id) }
                        }
                        Text("Step size: \(Int(settings.stepSize * 100))%")
                        Slider(value: $settings.stepSize, in: 0.02...0.25)
                    }.padding(6)
                }
                Spacer()
            }
            .frame(width: 280)

            // Right: devices with balance adjustments
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("Speakers") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(state.speakers) { s in
                            deviceRow(id: s.id, name: s.name,
                                      trim: volumeTrimBinding(s.id))
                        }
                        Text("Adjustment shifts a device's real output. Bars in the menu keep showing the shared level.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(6)
                }
                GroupBox("Displays") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(state.displays) { d in
                            deviceRow(id: d.id, name: d.name,
                                      trim: brightnessTrimBinding(d.id))
                        }
                    }.padding(6)
                }
                Spacer()
            }
            .frame(width: 340)
        }
        .padding(20)
        .frame(width: 680, height: 420)
    }

    private func deviceRow(id: String, name: String, trim: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(name, isOn: enabledBinding(id))
                Spacer()
                Text(trimLabel(trim.wrappedValue))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: trim, in: -0.5...0.5)
        }
    }

    private func trimLabel(_ v: Double) -> String {
        let pct = Int((v * 100).rounded())
        return pct == 0 ? "no adjustment" : (pct > 0 ? "+\(pct)%" : "\(pct)%")
    }

    private func enabledBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { settings.isEnabled(id) },
                set: { settings.setEnabled(id, $0) })
    }

    private func volumeTrimBinding(_ id: String) -> Binding<Double> {
        Binding(get: { settings.volumeTrims[id] ?? 0 },
                set: { settings.volumeTrims[id] = $0; state.reapplyVolume(id: id) })
    }

    private func brightnessTrimBinding(_ id: String) -> Binding<Double> {
        Binding(get: { settings.brightnessTrims[id] ?? 0 },
                set: { settings.brightnessTrims[id] = $0; state.reapplyBrightness(id: id) })
    }
}
