import CoreText
import Foundation

/// Registers the bundled Courier Prime fonts for this process.
///
/// Done in code rather than with Info.plist's ATSApplicationFontsPath so there is a single
/// mechanism. Under `swift run` there is no bundle Fonts folder, so this is a no-op and
/// Theme falls back to Courier New.
enum AppFonts {
    static func register() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }

        for url in files where url.pathExtension.lowercased() == "ttf" {
            // Failure means already registered or unreadable; either way the fallback font covers it.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
