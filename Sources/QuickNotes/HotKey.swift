import Carbon.HIToolbox

/// The global shortcut. To change it, edit these three values.
/// The combo must include Control or Command: macOS 15+ rejects Option-only
/// and Option+Shift-only hotkeys.
enum HotKeyConfig {
    static let keyCode = UInt32(kVK_ANSI_N)
    static let modifiers = UInt32(controlKey | optionKey)
    static let display = "⌃⌥N"
}

/// System-wide hotkey via Carbon. Needs no Accessibility permission and
/// consumes the keystroke so the frontmost app never sees it.
@MainActor
final class HotKey {
    private let action: () -> Void

    /// Returns nil when the combo can't be registered (usually taken by another app).
    /// The registration lives for the rest of the process; there's no unregister.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
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
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers hotkey events on the main thread.
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1, &eventType, userData, &handlerRef
        )
        guard installStatus == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x514E_5445), id: 1) // 'QNTE'
        let registerStatus = RegisterEventHotKey(
            keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registerStatus == noErr else {
            RemoveEventHandler(handlerRef)
            return nil
        }
    }
}
