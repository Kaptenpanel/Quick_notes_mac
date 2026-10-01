import AppKit
import QuickNotesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = NotesController(store: NoteStore(fileURL: NoteStore.defaultFileURL))
    /// Created on first show, so a hidden launch at login never builds the window or its views.
    private lazy var windowController = MainWindowController(controller: controller)
    private var hotKey: HotKey?
    private var captureHotKey: HotKey?
    private var isCapturing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Read first: the launch Apple Event is only current here, and a modal alert would replace it.
        let launchedAtLogin = LoginItem.launchedAtLogin
        NSApp.mainMenu = MainMenu.build()

        if controller.loadError != nil {
            showLoadErrorAlert()
        } else if let recovered = controller.recoveredFileURL {
            showRecoveredFileAlert(recovered)
        }

        hotKey = HotKey(keyCode: HotKeyConfig.keyCode, modifiers: HotKeyConfig.modifiers) { [weak self] in
            self?.newNote(nil)
        }
        captureHotKey = HotKey(
            keyCode: CaptureHotKeyConfig.keyCode, modifiers: CaptureHotKeyConfig.modifiers
        ) { [weak self] in
            self?.captureText(nil)
        }
        // Not worth an alert: the File menu item still works while Quick Notes is active.
        if captureHotKey == nil { NSLog("QuickNotes: \(CaptureHotKeyConfig.display) is unavailable") }

        LoginItem.registerOnFirstLaunch()

        // At login, stay out of the way until the hotkey or Dock icon is used.
        if !launchedAtLogin {
            if controller.notes.isEmpty { controller.newNote() }
            windowController.show()
        }

        if hotKey == nil { showHotKeyUnavailableAlert() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillResignActive(_ notification: Notification) {
        controller.flush()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller.flush()
        guard controller.hasUnsavedChanges else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Your latest notes couldn't be saved"
        alert.informativeText = """
            \(controller.saveError ?? "The notes file couldn't be written.") \
            If you quit now, unsaved text will be lost. Copy anything important first.
            """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Don't Quit")
        alert.addButton(withTitle: "Quit Anyway")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    // MARK: Menu actions

    @objc func newNote(_ sender: Any?) {
        controller.newNote()
        windowController.show()
    }

    /// Select part of the screen; its text becomes a new note.
    @objc func captureText(_ sender: Any?) {
        guard !controller.isReadOnly, !isCapturing else { return }
        isCapturing = true
        Task {
            defer { isCapturing = false }
            let image: CGImage
            do {
                guard let captured = try await ScreenCapture.captureRegion() else { return } // Esc
                image = captured
            } catch ScreenCapture.Failure.permissionDenied {
                showScreenRecordingAlert()
                return
            } catch {
                NSLog("QuickNotes: screen capture failed: \(error)")
                NSSound.beep()
                return
            }
            do {
                let text = try await TextRecognizer.recognizeText(in: image)
                controller.newNote(body: text)
                windowController.show()
            } catch {
                NSLog("QuickNotes: text recognition failed: \(error)")
                NSSound.beep()
            }
        }
    }

    // MARK: Alerts

    private func showHotKeyUnavailableAlert() {
        let alert = NSAlert()
        alert.messageText = "\(HotKeyConfig.display) is unavailable"
        alert.informativeText = """
            Another app is already using \(HotKeyConfig.display), so the Quick Notes shortcut won't work. \
            The README explains how to pick a different shortcut. \
            You can still use the window and ⌘N.
            """
        alert.runModal()
    }

    private func showScreenRecordingAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Quick Notes needs Screen Recording permission"
        alert.informativeText = """
            To read text from the screen, turn on Quick Notes in System Settings ▸ \
            Privacy & Security ▸ Screen & System Audio Recording, then quit and reopen Quick Notes.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // Adds Quick Notes to that list (and asks once) so there's a switch to turn on.
        CGRequestScreenCaptureAccess()
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }

    private func showLoadErrorAlert() {
        let alert = NSAlert()
        alert.messageText = "Couldn't read your notes"
        alert.informativeText = """
            The notes file at \(NoteStore.defaultFileURL.path) couldn't be read, \
            so editing is turned off to protect it. Check the file's permissions, then relaunch.
            """
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func showRecoveredFileAlert(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Your notes file was damaged"
        alert.informativeText = """
            It couldn't be opened, so Quick Notes set it aside and started fresh. \
            The damaged file and your last backup are kept in the same folder.
            """
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

enum MainMenu {
    @MainActor
    static func build() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Quick Notes",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Quick Notes", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Quick Notes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "Quick Notes")

        let fileMenu = NSMenu(title: "File")
        // No target: AppDelegate receives it through the responder chain.
        fileMenu.addItem(withTitle: "New Note", action: #selector(AppDelegate.newNote(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Capture Text from Screen",
                         action: #selector(AppDelegate.captureText(_:)), keyEquivalent: "s")
            .keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu: fileMenu, title: "File")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: editMenu, title: "Edit")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Keep on Top",
                           action: #selector(MainWindowController.toggleKeepOnTop(_:)), keyEquivalent: "t")
            .keyEquivalentModifierMask = [.command, .shift]
        main.addItem(submenu: windowMenu, title: "Window")
        NSApp.windowsMenu = windowMenu

        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
