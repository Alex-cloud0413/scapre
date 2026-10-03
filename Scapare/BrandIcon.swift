import AppKit

/// The shared LongJuan mark, with a transparent template for the menu bar.
enum BrandIcon {
    static func draw(in rect: NSRect, lineWidth: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + x * rect.width, y: rect.maxY - y * rect.height)
        }
        path.move(to: point(0.05, 0.38))
        path.line(to: point(0.05, 0.025))
        path.line(to: point(0.45, 0.025))
        path.move(to: point(0.95, 0.25))
        path.line(to: point(0.95, 0.605))
        path.line(to: point(0.55, 0.605))
        path.move(to: point(0.5, 0.76))
        path.line(to: point(0.5, 0.975))
        NSColor.black.setStroke()
        path.stroke()
    }

    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 20), flipped: false) { _ in
            draw(in: NSRect(x: 3, y: 1.5, width: 12, height: 17), lineWidth: 1.4)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Scapare"
        return image
    }
}
