import SwiftUI

struct DeviceSliderRow: View {
    let title: String
    let systemImage: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: systemImage).frame(width: 16)
                Slider(value: $value, in: 0...1)
                Text("\(Int(value * 100))").font(.caption.monospacedDigit()).frame(width: 30, alignment: .trailing)
            }
        }
    }
}
