import AppKit
import ServiceManagement

enum LoginItem {
    private static let registeredKey = "didRegisterLoginItem"

    /// Registers the app to open at login once, on first launch. Never re-registers,
    /// so turning it off in System Settings → General → Login Items sticks.
    @MainActor
    static func registerOnFirstLaunch() {
        // Only a real .app bundle can be a login item; skip `swift run` builds.
        guard Bundle.main.bundleIdentifier != nil else { return }
        guard !UserDefaults.standard.bool(forKey: registeredKey) else { return }
        UserDefaults.standard.set(true, forKey: registeredKey)
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("QuickNotes: login item registration failed: \(error)")
        }
    }

    /// True when macOS opened the app at login rather than the user opening it.
    /// Must be read during launch, while the launch Apple Event is current.
    @MainActor
    static var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }
}
