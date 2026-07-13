import AppKit

// The logo mark as a monochrome template image for the menu bar: two
// speaker dots joined into a U, one sound from two speakers. Template
// rendering adapts it to the menu bar appearance automatically.
enum MenuBarIcon {
    @MainActor static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 5.4, y: 12.6))
            p.line(to: NSPoint(x: 5.4, y: 7.8))
            p.appendArc(withCenter: NSPoint(x: 9, y: 7.8), radius: 3.6,
                        startAngle: 180, endAngle: 0, clockwise: false)
            p.line(to: NSPoint(x: 12.6, y: 12.6))
            p.lineWidth = 1.7
            p.lineCapStyle = .round
            p.stroke()
            NSBezierPath(ovalIn: NSRect(x: 5.4 - 1.8, y: 12.8 - 1.8, width: 3.6, height: 3.6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 12.6 - 1.8, y: 12.8 - 1.8, width: 3.6, height: 3.6)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }()
}
