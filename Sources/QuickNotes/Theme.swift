import AppKit
import SwiftUI

/// Colors from the design: "night desk" in dark mode, "smooth" paper in light mode.
/// Every color follows the system appearance on its own.
enum Palette {
    static let windowBackground = dynamic(light: 0xF1ECE1, dark: 0x161D27)
    static let titleText = dynamic(light: 0x7A7262, dark: 0x9AA7B8)
    static let accent = dynamic(light: 0xD9A11C, dark: 0xE3B04B)
    static let text = dynamic(light: 0x1E1B16, dark: 0xE4E9F0)
    static let placeholder = dynamic(light: 0x8C8474, dark: 0x6E7C8F)
    static let secondaryText = dynamic(light: 0x8C8474, dark: 0x8392A6)

    static let fieldBackground = dynamic(light: 0xFBF8F1, dark: 0x1C2531)
    static let fieldBorder = dynamic(light: 0xDDD5C5, dark: 0x2A3544)
    static let fieldBorderFocused = dynamic(light: 0xB3A993, dark: 0x4A5A70)

    static let addButton = dynamic(light: 0xE4DDCE, dark: 0x2A3544)
    static let addButtonHover = dynamic(light: 0x1E1B16, dark: 0xE3B04B)
    static let addButtonHoverText = dynamic(light: 0xF4EFE3, dark: 0x161D27)

    static let row = dynamic(light: 0x3A352C, dark: 0xC9D2DE)
    static let rowSelected = dynamic(light: 0xE4DDCE, dark: 0xD6CFBF)
    static let rowSelectedText = dynamic(light: 0x1E1B16, dark: 0x161D27)
    static let rowDate = dynamic(light: 0x9A9282, dark: 0x6E7C8F)
    static let rowDateSelected = dynamic(light: 0x6B6456, dark: 0x4A5566)

    static let editorBackground = dynamic(light: 0xFBF8F1, dark: 0x10161E)
    static let editorBorder = dynamic(light: 0xE4DDCE, dark: 0x222C39)
    static let rule = dynamic(light: 0xE6E9EC, dark: 0x1A2330)
    static let margin = dynamic(light: 0xD9A11C, dark: 0xE3B04B, lightAlpha: 0.4, darkAlpha: 0.35)

    static let actionHover = dynamic(light: 0xEFE9DC, dark: 0x1C2531)
    static let destructive = dynamic(light: 0xB8543F, dark: 0xE88B7A)

    private static func dynamic(
        light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1
    ) -> NSColor {
        // Built once; the provider runs on every draw and just picks one.
        let lightColor: NSColor = rgb(light, alpha: lightAlpha)
        let darkColor: NSColor = rgb(dark, alpha: darkAlpha)
        return NSColor(name: nil) { (appearance: NSAppearance) -> NSColor in
            let names: [NSAppearance.Name] = [.aqua, .darkAqua]
            let isDark: Bool = appearance.bestMatch(from: names) == NSAppearance.Name.darkAqua
            return isDark ? darkColor : lightColor
        }
    }

    private static func rgb(_ hex: UInt32, alpha: CGFloat) -> NSColor {
        let r: UInt32 = (hex >> 16) & 0xFF
        let g: UInt32 = (hex >> 8) & 0xFF
        let b: UInt32 = hex & 0xFF
        return NSColor(srgbRed: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: alpha)
    }
}

extension NSColor {
    var color: Color { Color(nsColor: self) }
}

/// Courier Prime, bundled in Resources/Fonts and registered by macOS at launch through
/// ATSApplicationFontsPath in Info.plist. Falls back to the system monospaced font
/// (e.g. under `swift run`, where there's no app bundle).
enum Typeface {
    private static let regularName = "CourierPrime-Regular"
    private static let boldName = "CourierPrime-Bold"

    static func nsFont(size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? boldName : regularName, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    static func font(size: CGFloat, bold: Bool = false) -> Font {
        Font(nsFont(size: size, bold: bold))
    }
}
