import AppKit

/// Generates custom menu bar icons matching the app's waveform+cursor design.
enum MenuBarIcon {

    /// Idle icon: 5 waveform bars + text cursor, monochrome template.
    static func idle() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipping: false) { rect in
            let barWidths: CGFloat = 2.0
            let gap: CGFloat = 2.0
            let barHeights: [CGFloat] = [5, 9, 14, 9, 5]
            let totalBarsWidth = CGFloat(barHeights.count) * barWidths + CGFloat(barHeights.count - 1) * gap
            let cursorWidth: CGFloat = 1.0
            let cursorGap: CGFloat = 2.5
            let totalWidth = totalBarsWidth + cursorGap + cursorWidth
            let startX = (rect.width - totalWidth) / 2

            NSColor.black.setFill()

            // Draw bars
            for (i, h) in barHeights.enumerated() {
                let x = startX + CGFloat(i) * (barWidths + gap)
                let y = (rect.height - h) / 2
                let bar = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barWidths, height: h), xRadius: 1, yRadius: 1)
                bar.fill()
            }

            // Draw cursor line
            let cursorX = startX + totalBarsWidth + cursorGap
            let cursorH: CGFloat = 12
            let cursorY = (rect.height - cursorH) / 2
            let cursor = NSBezierPath(rect: NSRect(x: cursorX, y: cursorY, width: cursorWidth, height: cursorH))
            cursor.fill()

            // Cursor serifs
            let serifW: CGFloat = 3
            let serifH: CGFloat = 1
            let serifX = cursorX - (serifW - cursorWidth) / 2
            NSBezierPath(rect: NSRect(x: serifX, y: cursorY, width: serifW, height: serifH)).fill()
            NSBezierPath(rect: NSRect(x: serifX, y: cursorY + cursorH - serifH, width: serifW, height: serifH)).fill()

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Recording icon: animated waveform bars (taller), no cursor.
    static func recording() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipping: false) { rect in
            let barWidths: CGFloat = 2.0
            let gap: CGFloat = 2.0
            let barHeights: [CGFloat] = [8, 14, 10, 16, 6]
            let totalWidth = CGFloat(barHeights.count) * barWidths + CGFloat(barHeights.count - 1) * gap
            let startX = (rect.width - totalWidth) / 2

            NSColor.black.setFill()

            for (i, h) in barHeights.enumerated() {
                let x = startX + CGFloat(i) * (barWidths + gap)
                let y = (rect.height - h) / 2
                let bar = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barWidths, height: h), xRadius: 1, yRadius: 1)
                bar.fill()
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}
