import AppKit

// NSApplication.delegate is weak; this global keeps the delegate alive.
let delegate = MainActor.assumeIsolated { AppDelegate() }
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
