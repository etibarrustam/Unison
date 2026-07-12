import SwiftUI

// Small info popover used across Settings.
struct InfoButton: View {
    let text: String
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .imageScale(.small)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            Text(text)
                .font(.callout)
                .padding(12)
                .frame(width: 280, alignment: .leading)
        }
    }
}
