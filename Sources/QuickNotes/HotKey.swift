import Carbon.HIToolbox

/// The global shortcuts. To change one, edit its three values.
/// A combo must include Control or Command: macOS 15+ rejects Option-only
/// and Option+Shift-only hotkeys.
enum HotKeyConfig {
    static let keyCode = UInt32(kVK_ANSI_N)
    static let modifiers = UInt32(controlKey | optionKey)
    static let display = "⌃⌥N"
}

/// Screen capture: select a region, and its text becomes a new note.
enum CaptureHotKeyConfig {
    static let keyCode = UInt32(kVK_ANSI_S)
    static let modifiers = UInt32(cmdKey | shiftKey)
    static let display = "⇧⌘S"
}

/// System-wide hotkey via Carbon. Needs no Accessibility permission and
/// consumes the keystroke so the frontmost app never sees it.
@MainActor
final class HotKey {
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private let action: () -> Void

    /// Returns nil when the combo can't be registered (usually taken by another app).
    /// The registration lives for the rest of the process; there's no unregister.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        self.action = action
        var handlerRef: EventHandlerRef?
        var hotKeyRef: EventHotKeyRef?

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // The C callback can't capture context, so the instance travels as userData.
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                // Every HotKey's handler sees every hotkey press; only act on our own.
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
                )
                // Carbon delivers hotkey events on the main thread.
                guard status == noErr, MainActor.assumeIsolated({ pressed.id == hotKey.id }) else {
                    return OSStatus(eventNotHandledErr)
                }
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1, &eventType, userData, &handlerRef
        )
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x514E_5445), id: id) // 'QNTE'
        let registerStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registerStatus == noErr else {
            RemoveEventHandler(handlerRef)
            return nil
        }
    }
}
