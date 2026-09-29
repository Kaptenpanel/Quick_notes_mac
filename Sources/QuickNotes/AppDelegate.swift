import AppKit
import QuickNotesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = NotesController(store: NoteStore(fileURL: NoteStore.defaultFileURL))
    private var windowController: MainWindowController!
    private var hotKey: HotKey?
    private var launchedAtLogin = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        launchedAtLogin = LoginItem.launchedAtLogin
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        windowController = MainWindowController(controller: controller)

        if controller.loadError != nil {
            showLoadErrorAlert()
        }

        hotKey = HotKey(keyCode: HotKeyConfig.keyCode, modifiers: HotKeyConfig.modifiers) { [weak self] in
            self?.newNote(nil)
        }

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

    func applicationWillTerminate(_ notification: Notification) {
        controller.flush()
    }

    // MARK: Menu actions

    @objc func newNote(_ sender: Any?) {
        controller.newNote()
        windowController.show()
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

    private func showLoadErrorAlert() {
        let alert = NSAlert()
        alert.messageText = "Couldn't read your notes"
        alert.informativeText = """
            The notes file at \(NoteStore.defaultFileURL.path) couldn't be read, \
            so saving is turned off to protect it. Check the file's permissions, then relaunch.
            """
        alert.alertStyle = .warning
        alert.runModal()
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
