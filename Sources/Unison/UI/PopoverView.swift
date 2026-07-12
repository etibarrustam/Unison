import SwiftUI

struct PopoverView: View {
    @ObservedObject var state: AppState
    @State private var allBrightness: Double = 0.7
    @State private var allVolume: Double = 0.3

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Left: Brightness
            VStack(alignment: .leading, spacing: 12) {
                Text("Brightness").font(.headline)
                DeviceSliderRow(title: "All Displays", systemImage: "sun.max.fill",
                                value: Binding(get: { allBrightness },
                                               set: { allBrightness = $0; state.setAllBrightness($0) }))
                Divider()
                ForEach($state.displays) { $d in
                    DeviceSliderRow(title: d.name, systemImage: "display",
                                    value: Binding(get: { d.brightness },
                                                   set: { state.setBrightness(id: d.id, $0) }))
                }
            }.frame(width: 220)

            Divider()

            // Right: Sound
            VStack(alignment: .leading, spacing: 12) {
                Text("Sound").font(.headline)
                DeviceSliderRow(title: "All Speakers", systemImage: "speaker.wave.3.fill",
                                value: Binding(get: { allVolume },
                                               set: { allVolume = $0; state.setAllVolume($0) }))
                Divider()
                ForEach($state.speakers) { $s in
                    DeviceSliderRow(title: s.name, systemImage: "hifispeaker",
                                    value: Binding(get: { s.volume },
                                                   set: { state.setVolume(id: s.id, $0) }))
                }
            }.frame(width: 220)
        }
        .padding()
        Divider()
        HStack {
            Button("Settings") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }.padding(.horizontal).padding(.bottom, 8)
    }
}
