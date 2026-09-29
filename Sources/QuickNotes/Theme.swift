import AppKit
import SwiftUI

/// Retro paper palette and Courier Prime type. Colors follow the system appearance.
enum Theme {
    static let chrome = dynamic(light: 0xF2EEE3, dark: 0x211E19)     // header + sidebar
    static let paper = dynamic(light: 0xFAF7F0, dark: 0x16140F)      // editor + search field
    static let ink = dynamic(light: 0x1E1B16, dark: 0xF2EEE3)        // text
    static let divider = dynamic(light: 0x1E1B16, dark: 0x3A362E)   // structural lines only
    static let fieldBorder = dynamic(light: 0x1E1B16, dark: 0x8F897C) // stays >= 3:1 on paper and chrome
    static let muted = dynamic(light: 0x8A8579, dark: 0x8F897C)
    static let accent = dynamic(light: 0xEDB220, dark: 0xEDB220)
    static let rowSelected = dynamic(light: 0x1E1B16, dark: 0xF2EEE3)
    static let rowSelectedText = dynamic(light: 0xFAF7F0, dark: 0x1E1B16)
    /// "+" button: ink square with paper glyph, inverted in dark mode.
    static let buttonFill = rowSelected
    static let buttonText = rowSelectedText
    /// Notebook rules under each editor line; faint so text stays dominant.
    static let rule = dynamicNS(light: 0xE6DFCF, dark: 0x2B2821)

    /// Courier Prime when bundled, else Courier New, else the system monospaced font.
    static func mono(_ size: CGFloat, bold: Bool = false) -> Font {
        Font(monoNSFont(size, bold: bold))
    }

    static func monoNSFont(_ size: CGFloat, bold: Bool = false) -> NSFont {
        let names = bold ? ["CourierPrime-Bold", "CourierNewPS-BoldMT"] : ["CourierPrime-Regular", "Courier Prime", "CourierNewPSMT"]
        for name in names {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: dynamicNS(light: light, dark: dark))
    }

    private static func dynamicNS(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return rgb(isDark ? dark : light)
        }
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
