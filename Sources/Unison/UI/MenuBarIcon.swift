import AppKit

// The logo mark as a monochrome template image for the menu bar: two
// speakers radiating sound outward. Template rendering adapts it to the
// menu bar appearance automatically.
enum MenuBarIcon {
    @MainActor static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            for x: CGFloat in [6.8, 11.2] {
                NSBezierPath(ovalIn: NSRect(x: x - 1.7, y: 9 - 1.7, width: 3.4, height: 3.4)).fill()
            }
            func arc(_ cx: CGFloat, _ r: CGFloat, _ from: CGFloat, _ to: CGFloat) {
                let p = NSBezierPath()
                p.appendArc(withCenter: NSPoint(x: cx, y: 9), radius: r,
                            startAngle: from, endAngle: to)
                p.lineWidth = 1.5
                p.lineCapStyle = .round
                p.stroke()
            }
            arc(6.8, 3.4, 125, 235)
            arc(6.8, 5.6, 125, 235)
            arc(11.2, 3.4, -55, 55)
            arc(11.2, 5.6, -55, 55)
            return true
        }
        img.isTemplate = true
        return img
    }()
}
