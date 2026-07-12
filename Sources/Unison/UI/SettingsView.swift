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
                        row(Toggle("Launch at login", isOn: $settings.launchAtLogin),
                            info: "Starts Unison automatically when you log in, so keyboard control works from the first key press.")
                        row(Toggle("Show menu bar icon", isOn: $settings.menuIconVisible),
                            info: "Hides the slider icon in the menu bar, also after restarts. To bring it back, open the Unison app again (Spotlight or Finder), and the icon reappears.")
                    }.padding(6)
                }
                GroupBox("Overlay") {
                    VStack(alignment: .leading, spacing: 8) {
                        row(Toggle("Custom volume overlay", isOn: $settings.hudVolume),
                            info: "Shows Unison's overlay with an accurate level bar when you press volume keys. Off uses the macOS bezel instead; on macOS Tahoe the system bezel cannot display the real level.")
                        row(Toggle("Custom brightness overlay", isOn: $settings.hudBrightness),
                            info: "Same as the volume overlay, for the brightness keys.")
                    }.padding(6)
                }
                GroupBox("Keyboard") {
                    VStack(alignment: .leading, spacing: 8) {
                        row(Picker("Volume keys control", selection: $settings.keyboardTarget) {
                            Text("All devices").tag("all")
                            ForEach(state.speakers) { Text($0.name).tag($0.id) }
                        }, info: "Which speakers the volume keys change. All devices moves everything together and keeps your balance; a single device leaves the others untouched.")
                        row(Picker("Brightness keys control", selection: $settings.keyboardBrightnessTarget) {
                            Text("All displays").tag("all")
                            ForEach(state.displays) { Text($0.name).tag($0.id) }
                        }, info: "Which displays the brightness keys change.")
                        HStack {
                            Text("Step size: \(Int(settings.stepSize * 100))%")
                            InfoButton(text: "How much one key press changes the level. macOS uses about 6%.")
                        }
                        Slider(value: $settings.stepSize, in: 0.02...0.25)
                    }.padding(6)
                }
                Spacer()
            }
            .frame(width: 280)

            // Right: devices with balance adjustments
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(state.speakers) { s in
                            deviceRow(id: s.id, name: s.name,
                                      scale: volumeScaleBinding(s.id))
                        }
                    }.padding(6)
                } label: {
                    HStack {
                        Text("Speakers")
                        InfoButton(text: "Untick a device to remove it from the menu and from group control; its level stays where it was. Max output caps a device relative to the rest: zero stays zero for everyone, levels rise together, and a device at 80% always sits below the others. Use it to keep one speaker quieter or one display dimmer at any volume.")
                    }
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(state.displays) { d in
                            deviceRow(id: d.id, name: d.name,
                                      scale: brightnessScaleBinding(d.id))
                        }
                    }.padding(6)
                } label: {
                    HStack {
                        Text("Displays")
                        InfoButton(text: "Works like the speaker settings: untick to exclude a display, and use max output to keep one display dimmer than the other at every brightness level.")
                    }
                }
                Spacer()
            }
            .frame(width: 340)
        }
        .padding(20)
        .frame(width: 680, height: 440)
    }

    private func row(_ content: some View, info: String) -> some View {
        HStack(spacing: 6) {
            content
            InfoButton(text: info)
            Spacer(minLength: 0)
        }
    }

    private func deviceRow(id: String, name: String, scale: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(name, isOn: enabledBinding(id))
                Spacer()
                Text(scaleLabel(scale.wrappedValue))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: scale, in: 0.1...1.0)
        }
    }

    private func scaleLabel(_ v: Double) -> String {
        let pct = Int((v * 100).rounded())
        return pct >= 100 ? "full output" : "max output \(pct)%"
    }

    private func enabledBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { settings.isEnabled(id) },
                set: { settings.setEnabled(id, $0) })
    }

    private func volumeScaleBinding(_ id: String) -> Binding<Double> {
        Binding(get: { settings.volumeScales[id] ?? 1 },
                set: { settings.volumeScales[id] = $0; state.reapplyVolume(id: id) })
    }

    private func brightnessScaleBinding(_ id: String) -> Binding<Double> {
        Binding(get: { settings.brightnessScales[id] ?? 1 },
                set: { settings.brightnessScales[id] = $0; state.reapplyBrightness(id: id) })
    }
}
