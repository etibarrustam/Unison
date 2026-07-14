import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var state: AppState
    var spatial: SpatialEngine? = nil

    var body: some View {
        // Scrollable: with several devices the right column grows past any
        // fixed height, and clipped content cannot be reached otherwise.
        ScrollView(.vertical) {
            columns
                .padding(20)
        }
        .frame(width: 680)
        .frame(minHeight: 420, idealHeight: 560, maxHeight: 720)
        .onAppear {
            // Device ids can change (replug, id scheme); a stale keyboard
            // target would leave the picker blank and silently act as all.
            if settings.keyboardTarget != "all",
               !state.speakers.contains(where: { $0.id == settings.keyboardTarget }) {
                settings.keyboardTarget = "all"
            }
            if settings.keyboardBrightnessTarget != "all",
               !state.displays.contains(where: { $0.id == settings.keyboardBrightnessTarget }) {
                settings.keyboardBrightnessTarget = "all"
            }
        }
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: 20) {
            // Left: app behavior
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("General") {
                    VStack(alignment: .leading, spacing: 8) {
                        row(Toggle("Launch at login", isOn: $settings.launchAtLogin),
                            info: "Starts Unison automatically when you log in, so keyboard control works from the first key press.")
                        row(Toggle("Show menu bar icon", isOn: $settings.menuIconVisible),
                            info: "Hides the slider icon in the menu bar, also after restarts. The keyboard keeps working. To reach Unison again, open the app (Spotlight or Finder): this window appears without restarting anything, and you can turn the icon back on here.")
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
            }
            .frame(width: 280)

            // Right: devices with balance adjustments
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        if let soloName {
                            Text("Playing on \(soloName). Other speakers and stereo positions apply when Unison is the selected output.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(state.speakers) { s in
                            let inactive = state.soloSpeakerID != nil && s.id != state.soloSpeakerID
                            Group {
                                deviceRow(id: s.id, name: s.name,
                                          scale: volumeScaleBinding(s.id))
                                if settings.spatialEnabled && spatial?.isRunning != true && s.pannable {
                                    positionRow(s.id)
                                }
                            }
                            .disabled(inactive)
                            .opacity(inactive ? 0.35 : 1)
                        }
                        Group {
                            HStack {
                                Toggle("Stereo positions", isOn: $settings.spatialEnabled)
                                InfoButton(text: "Place every physical speaker where it sits, from full left to full right. Each speaker then plays the part of the stereo field matching its location, so stereo and 8D audio image correctly across all devices, including ones behind you. Off keeps playing through all ticked devices with their natural stereo, just without positioning. Works with any output selected in the sound settings; no Audio MIDI Setup needed. macOS asks once for the System Audio Recording permission.")
                                Spacer(minLength: 0)
                                Button("Reset") { resetStereoAdjustments() }
                                    .buttonStyle(.link).font(.caption)
                                    .help("Return every speaker position to center")
                            }
                            .onChange(of: settings.spatialEnabled) { _, on in
                                // The engine keeps playing through all devices
                                // either way; the toggle only changes the mix.
                                spatial?.applyMix(positions: on ? settings.spatialPositions : nil)
                                state.applyAll()
                            }
                            spatialSection
                        }
                        .disabled(state.soloSpeakerID != nil)
                        .opacity(state.soloSpeakerID != nil ? 0.35 : 1)
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
            }
            .frame(width: 340)
        }
    }

    private var soloName: String? {
        guard let solo = state.soloSpeakerID else { return nil }
        return state.speakers.first { $0.id == solo }?.name
    }

    // Clears both kinds of stereo adjustment: the engine's per-channel
    // positions and the per-device pans used when the engine is off.
    private func resetStereoAdjustments() {
        settings.spatialPositions = [:]
        settings.speakerPans = [:]
        spatial?.applyMix(positions: settings.spatialEnabled ? [:] : nil)
        state.applyAll()
    }

    private func row(_ content: some View, info: String) -> some View {
        HStack(spacing: 6) {
            content
            InfoButton(text: info)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var spatialSection: some View {
        if let spatial {
            if spatial.isRunning {
                Divider()
                Text("Play through")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(spatial.outputDeviceList()) { dev in
                    Toggle(dev.name, isOn: spatialIncludedBinding(dev.uid))
                    if settings.spatialEnabled, !settings.spatialExcluded.contains(dev.uid) {
                        ForEach(spatial.availableSpeakers().filter { $0.deviceUID == dev.uid }) { sp in
                            spatialSliderRow(sp, spatial: spatial)
                        }
                    }
                }
            } else if spatial.captureDenied {
                VStack(alignment: .leading, spacing: 6) {
                    Text("macOS blocked Unison from reading system audio. Allow Unison under System Audio Recording Only, then switch Stereo positions off and on.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
    }

    private func spatialSliderRow(_ sp: SpatialSpeaker, spatial: SpatialEngine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sp.name).font(.caption)
            HStack(spacing: 8) {
                Text("L").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { settings.spatialPositions[sp.id] ?? 0.5 },
                    set: {
                        settings.spatialPositions[sp.id] = $0
                        spatial.applyMix(positions: settings.spatialPositions)
                    }
                ), in: 0...1)
                Text("R").font(.caption).foregroundStyle(.secondary)
                Text(panLabel(settings.spatialPositions[sp.id] ?? 0.5))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
        }
        .padding(.leading, 20)
    }

    private func spatialIncludedBinding(_ uid: String) -> Binding<Bool> {
        Binding(get: { !settings.spatialExcluded.contains(uid) },
                set: { on in
                    if on { settings.spatialExcluded.remove(uid) }
                    else { settings.spatialExcluded.insert(uid) }
                    _ = spatial?.start(positions: settings.spatialEnabled ? settings.spatialPositions : nil,
                                       excluded: settings.spatialExcluded)
                })
    }

    private func positionRow(_ id: String) -> some View {
        HStack(spacing: 8) {
            Text("L").font(.caption).foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { settings.pan(id) },
                set: { settings.speakerPans[id] = $0; state.reapplyVolume(id: id) }
            ), in: 0...1)
            Text("R").font(.caption).foregroundStyle(.secondary)
            Text(panLabel(settings.pan(id)))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.leading, 20)
    }

    private func panLabel(_ p: Double) -> String {
        let pct = Int(((p - 0.5) * 200).rounded())
        if pct == 0 { return "center" }
        return pct < 0 ? "\(-pct)% left" : "\(pct)% right"
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
