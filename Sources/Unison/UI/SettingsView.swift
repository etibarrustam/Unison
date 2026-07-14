import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var state: AppState
    var spatial: SpatialEngine? = nil
    @State private var showArrange = false

    var body: some View {
        // Scrollable: with several devices the right column grows past any
        // fixed height, and clipped content cannot be reached otherwise.
        ScrollView(.vertical) {
            columns
                .padding(20)
        }
        .frame(width: 680)
        .frame(minHeight: 420, idealHeight: 560, maxHeight: 720)
        .sheet(isPresented: $showArrange) {
            if let spatial {
                SpeakerArrangementView(settings: settings, spatial: spatial)
            }
        }
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
                        }, info: "Which speakers the volume keys change. All devices moves everything together and keeps your balance; a single device leaves the others untouched. While one device is selected in the sound output list, the keys control that device alone.")
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
                            Text("Playing on \(soloName). Other devices and stereo positions resume when Unison is the selected output.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(state.speakers) { s in
                            let inactive = soloActive && s.id != state.soloSpeakerID
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
                        HStack {
                            // Reads as Stereo while a single device plays;
                            // the stored preference survives and returns with
                            // the Unison output.
                            Picker("Sound mode", selection: soundModeBinding) {
                                Text("Stereo").tag("stereo")
                                Text("Mono").tag("mono")
                                Text("Spatial").tag("spatial")
                            }
                            .fixedSize()
                            InfoButton(text: "Stereo plays every ticked device with its natural left and right. Mono plays the complete mix on every speaker, best when speakers sit in different places or rooms so nobody hears only half the music. Spatial lets you drag every physical speaker to where it stands in your room, anywhere around you including behind, using Arrange Speakers; the macOS spatial mixer renders the matching part of the stereo field to each speaker, and nearer speakers are delayed a fraction so everything arrives at your seat together. Applies while Unison is the selected sound output; picking a single device plays through it alone until Unison is selected again. Reset returns every speaker to its natural stereo side. No Audio MIDI Setup needed. macOS asks once for the System Audio Recording permission.")
                            Spacer(minLength: 0)
                            Button("Reset") { resetStereoAdjustments() }
                                .buttonStyle(.link).font(.caption)
                                .help("Return every speaker to its natural stereo side")
                        }
                        .disabled(soloActive)
                        .opacity(soloActive ? 0.35 : 1)
                        .onChange(of: settings.soundMode) { _, _ in
                            // The engine keeps playing through all devices
                            // in every mode; the picker only changes the mix.
                            spatial?.applyMix(mode: settings.mixMode)
                            state.applyAll()
                        }
                        spatialSection
                            .disabled(soloActive)
                            .opacity(soloActive ? 0.35 : 1)
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

    private var soloActive: Bool { state.soloSpeakerID != nil }

    private var soloName: String? {
        guard let solo = state.soloSpeakerID else { return nil }
        return state.speakers.first { $0.id == solo }?.name
    }

    // Reads as Stereo and inert while a single device is selected in the
    // Sound list, without erasing the stored preference.
    private var soundModeBinding: Binding<String> {
        Binding(get: { soloActive ? "stereo" : settings.soundMode },
                set: { settings.soundMode = $0 })
    }

    // Clears every kind of stereo adjustment: room placements, the legacy
    // slider positions, and the per-device pans used when the engine is
    // off. Speakers return to their natural stereo sides.
    private func resetStereoAdjustments() {
        settings.speakerPlacements = [:]
        settings.spatialPositions = [:]
        settings.speakerPans = [:]
        spatial?.applyMix(mode: settings.mixMode)
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
                if settings.spatialEnabled {
                    Button("Arrange Speakers…") { showArrange = true }
                        .help("Drag every speaker to where it stands in your room, including behind you")
                }
                Divider()
                Text("Play through")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(spatial.outputDeviceList()) { dev in
                    Toggle(dev.name, isOn: spatialIncludedBinding(dev.uid))
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

    private func spatialIncludedBinding(_ uid: String) -> Binding<Bool> {
        Binding(get: { !settings.spatialExcluded.contains(uid) },
                set: { on in
                    if on { settings.spatialExcluded.remove(uid) }
                    else { settings.spatialExcluded.insert(uid) }
                    // Mix-level change: no engine rebuild, no dropout.
                    spatial?.setExcluded(settings.spatialExcluded, mode: settings.mixMode)
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
