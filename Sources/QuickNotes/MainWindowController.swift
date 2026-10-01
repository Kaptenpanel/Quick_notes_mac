import AppKit
import Observation
import QuickNotesCore
import SwiftUI

/// Floating on/off, persisted across launches. Defaults to off.
@MainActor
@Observable
final class PinState {
    // Renamed from "windowPinned" (which defaulted to on) so everyone starts unpinned.
    private static let key = "windowFloating"

    var isPinned: Bool {
        didSet {
            UserDefaults.standard.set(isPinned, forKey: Self.key)
            onChange?(isPinned)
        }
    }

    @ObservationIgnored var onChange: ((Bool) -> Void)?

    init() {
        isPinned = UserDefaults.standard.bool(forKey: Self.key)
    }
}

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private let controller: NotesController
    private let pin = PinState()

    init(controller: NotesController) {
        self.controller = controller

        let hosting = NSHostingController(rootView: ContentView(controller: controller, pin: pin))
        hosting.sceneBridgingOptions = []

        let window = NSWindow(contentViewController: hosting)
        window.title = "Quick Notes"
        // The design draws its own centered title; keep only the traffic lights.
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Palette.windowBackground
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentMinSize = NSSize(width: 560, height: 320)
        window.setContentSize(NSSize(width: 820, height: 540))
        window.center()
        window.setFrameAutosaveName("QuickNotesMainWindow")

        super.init(window: window)
        window.delegate = self

        applyPin(pin.isPinned)
        pin.onChange = { [weak self] in self?.applyPin($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        // Plain activate() is cooperative on macOS 14+ and may leave focus in the previous app.
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyPin(_ pinned: Bool) {
        window?.level = pinned ? .floating : .normal
    }

    // Window ▸ Keep on Top. Reached through the responder chain.
    @objc func toggleKeepOnTop(_ sender: Any?) {
        pin.isPinned.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleKeepOnTop(_:)) {
            menuItem.state = pin.isPinned ? .on : .off
        }
        return true
    }

    // Close hides; the app keeps running so the hotkey still works.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        controller.windowWillHide()
        sender.orderOut(nil)
        return false
    }

    func windowDidMiniaturize(_ notification: Notification) {
        controller.flush()
    }
}
