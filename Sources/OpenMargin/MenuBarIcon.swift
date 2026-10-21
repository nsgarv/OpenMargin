import AppKit

enum MenuBarIcon {
    static func image(listening: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            let page = NSBezierPath(
                roundedRect: NSRect(x: 2.4, y: 1.4, width: 13.2, height: 15.2),
                xRadius: 2,
                yRadius: 2
            )
            page.lineWidth = 1.35
            page.stroke()

            let rule = NSBezierPath()
            rule.move(to: NSPoint(x: 7.1, y: 3.1))
            rule.line(to: NSPoint(x: 7.1, y: 14.9))
            rule.lineWidth = 1.25
            rule.stroke()

            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: 9.1, y: 8.4))
            mark.line(to: NSPoint(x: 13.3, y: 8.4))
            mark.lineWidth = 1.45
            mark.lineCapStyle = .round
            mark.stroke()

            if listening {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 11.6, y: 11.2, width: 4.6, height: 4.6)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
