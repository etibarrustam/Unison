import SwiftUI

struct PopoverView: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings: Settings
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    private var enabledDisplays: [DisplayDevice] {
        state.displays.filter { settings.isEnabled($0.id) }
    }
    private var enabledSpeakers: [SpeakerDevice] {
        state.speakers.filter { settings.isEnabled($0.id) }
    }

    private func average(_ xs: [Double]) -> Double {
        xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Left: Brightness
            VStack(alignment: .leading, spacing: 12) {
                columnHeader("Brightness") { state.setAllBrightness(average(enabledDisplays.map(\.brightness))) }
                GroupSliderRow(title: "All Displays", systemImage: "sun.max.fill",
                               average: average(enabledDisplays.map(\.brightness)),
                               nudge: { state.nudgeAllBrightness($0) })
                Divider()
                ForEach(enabledDisplays) { d in
                    DeviceSliderRow(title: d.name, systemImage: "display",
                                    value: Binding(get: { d.brightness },
                                                   set: { state.setBrightness(id: d.id, $0) }))
                }
            }.frame(width: 220)

            Divider()

            // Right: Sound
            VStack(alignment: .leading, spacing: 12) {
                columnHeader("Sound") { state.setAllVolume(average(enabledSpeakers.map(\.volume))) }
                GroupSliderRow(title: "All Speakers", systemImage: "speaker.wave.3.fill",
                               average: average(enabledSpeakers.map(\.volume)),
                               nudge: { state.nudgeAllVolume($0) })
                Divider()
                ForEach(enabledSpeakers) { s in
                    DeviceSliderRow(title: s.name, systemImage: "hifispeaker",
                                    value: Binding(get: { s.volume },
                                                   set: { state.setVolume(id: s.id, $0) }))
                }
            }.frame(width: 220)
        }
        .padding()
        Divider()
        HStack {
            Button("Settings") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            Button("Refresh Devices") { state.refreshDevices() }
            Button("Help") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "help")
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }.padding(.horizontal).padding(.bottom, 8)
    }

    // Header with an Equalize action that levels the group to its average.
    private func columnHeader(_ title: String, equalize: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button("Equalize", action: equalize)
                .buttonStyle(.link)
                .font(.caption)
                .help("Set every device in this group to the same level")
        }
    }
}
