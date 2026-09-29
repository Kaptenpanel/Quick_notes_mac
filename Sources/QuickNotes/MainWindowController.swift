import AppKit
import Observation
import QuickNotesCore
import SwiftUI

/// Floating on/off, persisted across launches. Defaults to on.
@MainActor
@Observable
final class PinState {
    private static let key = "windowPinned"

    var isPinned: Bool {
        didSet {
            UserDefaults.standard.set(isPinned, forKey: Self.key)
            onChange?(isPinned)
        }
    }

    @ObservationIgnored var onChange: ((Bool) -> Void)?

    init() {
        isPinned = UserDefaults.standard.object(forKey: Self.key) as? Bool ?? true
    }
}

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let controller: NotesController
    private let pin = PinState()

    init(controller: NotesController) {
        self.controller = controller

        let hosting = NSHostingController(rootView: ContentView(controller: controller, pin: pin))
        // The SwiftUI header draws the title; nothing is bridged into the titlebar.
        hosting.sceneBridgingOptions = []

        let window = NSWindow(contentViewController: hosting)
        // Still used by Mission Control and the Window menu.
        window.title = "Quick Notes"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // On every desktop, always; pin only decides whether it floats.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentMinSize = NSSize(width: 520, height: 320)
        window.setContentSize(NSSize(width: 720, height: 460))
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
