import SwiftUI

// Slider for an "All" group. Owns its displayed value and emits deltas,
// so device clamping can never create a reconcile loop with the average.
struct GroupSliderRow: View {
    let title: String
    let systemImage: String
    let average: Double
    let nudge: (Double) -> Void

    @State private var ui: Double = 0
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: systemImage).frame(width: 16)
                Slider(value: Binding(
                    get: { ui },
                    set: { new in
                        let delta = new - ui
                        ui = new
                        nudge(delta)
                    }
                ), in: 0...1) { isEditing in
                    editing = isEditing
                    if !isEditing { ui = average }
                }
                Text("\(Int(ui * 100))").font(.caption.monospacedDigit()).frame(width: 30, alignment: .trailing)
            }
        }
        .onAppear { ui = average }
        .onChange(of: average) { _, new in
            if !editing { ui = new }
        }
    }
}
