import AppKit

/// Design option A2 "Press": side view of a key cap on a base line, with a downward
/// chevron above it. A template image; the inactive state is the same glyph dimmed.
enum MenuBarIcon {
    static let active = make(alpha: 1)
    static let inactive = make(alpha: 0.35)

    private static func make(alpha: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            draw(alpha: alpha)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Headset Button"
        return image
    }

    /// Coordinates are top-left origin, in points, on an 18 × 18 canvas.
    nonisolated private static func draw(alpha: CGFloat) {
        // Draw opaque into a transparency layer dimmed as a whole, so overlapping strokes stay even.
        let context = NSGraphicsContext.current?.cgContext
        context?.setAlpha(alpha)
        context?.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context?.endTransparencyLayer() }
        NSColor.black.setStroke()

        func stroke(_ path: NSBezierPath) {
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }

        // Downward chevron.
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: 6, y: 2))
        chevron.line(to: NSPoint(x: 9, y: 5))
        chevron.line(to: NSPoint(x: 12, y: 2))
        stroke(chevron)

        // Key cap, side view: a cap slightly narrower at the top, open at the bottom.
        let cap = NSBezierPath()
        cap.move(to: NSPoint(x: 4, y: 14))
        cap.line(to: NSPoint(x: 5, y: 9.5))
        cap.curve(
            to: NSPoint(x: 6.5, y: 8.5), controlPoint1: NSPoint(x: 5.2, y: 8.8), controlPoint2: NSPoint(x: 5.8, y: 8.5))
        cap.line(to: NSPoint(x: 11.5, y: 8.5))
        cap.curve(
            to: NSPoint(x: 13, y: 9.5), controlPoint1: NSPoint(x: 12.2, y: 8.5), controlPoint2: NSPoint(x: 12.8, y: 8.8)
        )
        cap.line(to: NSPoint(x: 14, y: 14))
        stroke(cap)

        // Base line.
        let base = NSBezierPath()
        base.move(to: NSPoint(x: 2, y: 15))
        base.line(to: NSPoint(x: 16, y: 15))
        stroke(base)
    }
}
