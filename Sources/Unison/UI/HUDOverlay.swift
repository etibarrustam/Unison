import AppKit
import SwiftUI

// Custom level HUD styled after the macOS Tahoe banner. The native OSD
// ignores the fill value on Tahoe, so we draw our own.
@MainActor
enum HUDOverlay {
    enum Kind { case volume, brightness, mute }

    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ kind: Kind, value: Double) {
        let icon: String
        switch kind {
        case .brightness: icon = "sun.max.fill"
        case .volume: icon = value == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill"
        case .mute: icon = value == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill"
        }

        let p = panel ?? makePanel()
        panel = p
        p.contentView = NSHostingView(rootView: HUDView(icon: icon, value: LevelMath.clamp(value)))
        position(p)
        p.alphaValue = 1
        p.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                p.animator().alphaValue = 0
            } completionHandler: {
                if hideWork?.isCancelled == false { p.orderOut(nil) }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 48),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return p
    }

    private static func position(_ p: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        p.setFrameOrigin(NSPoint(x: f.maxX - p.frame.width - 16,
                                 y: f.maxY - p.frame.height - 8))
    }
}

private struct HUDView: View {
    let icon: String
    let value: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 20)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(.primary)
                        .frame(width: max(6, geo.size.width * value))
                }
            }
            .frame(height: 6)
            Text("\(Int(value * 100))")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(width: 240, height: 48)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
