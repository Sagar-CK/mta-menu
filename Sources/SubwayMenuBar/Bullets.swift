import AppKit

/// Draws MTA-style route bullets (the colored circles with a letter) and
/// composes them into attributed strings for the menu bar and the dropdown.
enum Bullets {
    private static var cache: [String: NSImage] = [:]

    /// The letter shown inside the bullet. The three shuttles all read "S" on
    /// real signage; Staten Island Railway shows "SIR".
    static func label(for route: String) -> String {
        switch route {
        case "GS", "FS", "H": return "S"
        case "SI": return "SIR"
        default: return route
        }
    }

    static func image(for route: String, gtfs: GTFSStatic, size: CGFloat) -> NSImage {
        let key = "\(route)@\(size)"
        if let cached = cache[key] { return cached }
        let info = gtfs.route(route)
        let image = draw(label: label(for: route),
                         fill: NSColor(hex: info.color),
                         text: NSColor(hex: info.textColor),
                         size: size)
        cache[key] = image
        return image
    }

    private static func draw(label: String, fill: NSColor, text: NSColor, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(ovalIn: rect).fill()
            let fontSize = label.count > 1 ? size * 0.38 : size * 0.64
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: text,
            ]
            let string = NSAttributedString(string: label, attributes: attrs)
            let stringSize = string.size()
            string.draw(at: NSPoint(x: (size - stringSize.width) / 2,
                                    y: (size - stringSize.height) / 2 + size * 0.02))
            return true
        }
        return image
    }

    /// `[N] 2m  [A] 4m` for the status item button.
    static func menuBarTitle(_ entries: [MenuBarEntry], gtfs: GTFSStatic) -> NSAttributedString {
        let font = NSFont.menuBarFont(ofSize: 0)
        let result = NSMutableAttributedString()
        // No extra padding: the status bar already applies the same margins as other items.
        for (i, entry) in entries.enumerated() {
            if i > 0 { result.append(NSAttributedString(string: "    ", attributes: [.font: font])) }
            result.append(attachment(for: entry.route, gtfs: gtfs, size: 16, font: font))
            let text = entry.minutes == 0 ? "  now" : "  \(entry.minutes)m"
            result.append(NSAttributedString(string: text,
                                             attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
        }
        return result
    }

    /// A dropdown row: bullet, minutes, and destination.
    static func menuLine(route: String, minutes: Int, destination: String?, gtfs: GTFSStatic) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let result = NSMutableAttributedString()
        result.append(attachment(for: route, gtfs: gtfs, size: 18, font: font))
        let when = minutes == 0 ? "Now" : "\(minutes) min"
        result.append(NSAttributedString(string: "  \(when)",
                                         attributes: [.font: NSFont.menuFont(ofSize: 0).bold, .foregroundColor: NSColor.labelColor]))
        if let destination {
            result.append(NSAttributedString(string: "  →  \(destination)",
                                             attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        return result
    }

    /// A "Lines" submenu row: bullet followed by the line's long name.
    static func routeMenuTitle(_ info: RouteInfo, gtfs: GTFSStatic) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let result = NSMutableAttributedString()
        result.append(attachment(for: info.id, gtfs: gtfs, size: 16, font: font))
        result.append(NSAttributedString(string: "  \(info.longName)",
                                         attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
        return result
    }

    private static func attachment(for route: String, gtfs: GTFSStatic, size: CGFloat, font: NSFont) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = image(for: route, gtfs: gtfs, size: size)
        // Center the circle on the text's cap height.
        attachment.bounds = CGRect(x: 0, y: (font.capHeight - size) / 2, width: size, height: size)
        return NSAttributedString(attachment: attachment)
    }
}

extension NSColor {
    /// Creates a color from a `RRGGBB` hex string (no leading `#`).
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}

extension NSFont {
    var bold: NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask)
    }
}
