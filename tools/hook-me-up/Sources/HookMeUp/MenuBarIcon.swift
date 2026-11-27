import AppKit

/// The original app icon's hook, simplified for a small monochrome menu-bar template.
enum MenuBarIcon {
    static func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let hook = NSBezierPath()
            hook.lineWidth = 2
            hook.lineCapStyle = .round
            hook.lineJoinStyle = .round
            hook.move(to: NSPoint(x: 10, y: 13.5))
            hook.line(to: NSPoint(x: 10, y: 6.5))
            hook.curve(
                to: NSPoint(x: 3, y: 6.5), controlPoint1: NSPoint(x: 10, y: 1.4),
                controlPoint2: NSPoint(x: 3, y: 1.4))
            hook.line(to: NSPoint(x: 3, y: 8.2))
            hook.line(to: NSPoint(x: 4.5, y: 6.7))
            hook.stroke()
            let eye = NSBezierPath(ovalIn: NSRect(x: 8.4, y: 13.5, width: 3.2, height: 3.2))
            eye.lineWidth = 1.4
            eye.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Hook Me Up"
        return image
    }
}
