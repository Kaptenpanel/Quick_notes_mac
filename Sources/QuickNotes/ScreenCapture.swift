import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

/// Drag across part of a screen and get back its pixels. Esc or a plain click cancels.
///
/// Draws its own selection overlay instead of running `screencapture -i`: launched from a
/// hotkey while another app is active, that tool's UI never took focus, so the cursor
/// vanished and keystrokes landed in whatever was frontmost.
@MainActor
enum ScreenCapture {
    enum Failure: Error {
        /// Screen Recording is off for Quick Notes in System Settings.
        case permissionDenied
    }

    /// Returns nil if the user cancels.
    static func captureRegion() async throws -> CGImage? {
        // Check before covering the screen, so a system prompt can't end up under the overlay.
        guard CGPreflightScreenCaptureAccess() else { throw Failure.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let selection = await SelectionOverlay.run(),
              let display = content.displays.first(where: { $0.displayID == selection.displayID })
        else { return nil }

        // Leave out Quick Notes' own windows, including the overlay if it's still leaving the screen.
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])

        let scale = selection.scale
        let config = SCStreamConfiguration()
        // ScreenCaptureKit measures from the display's top left; AppKit from its bottom left.
        config.sourceRect = CGRect(
            x: selection.rect.minX,
            y: selection.screenHeight - selection.rect.maxY,
            width: selection.rect.width,
            height: selection.rect.height
        )
        config.width = Int(selection.rect.width * scale)
        config.height = Int(selection.rect.height * scale)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

// MARK: - Selection overlay

/// A dimmed, crosshair-cursor window over every screen for the duration of one drag.
@MainActor
private final class SelectionOverlay {
    struct Selection {
        let displayID: CGDirectDisplayID?
        let scale: CGFloat
        let screenHeight: CGFloat
        /// In the screen's own points, origin at its bottom left.
        let rect: CGRect
    }

    /// Keeps the overlay alive while it's on screen; only one runs at a time.
    private static var current: SelectionOverlay?

    static func run() async -> Selection? {
        await withCheckedContinuation { continuation in
            let overlay = SelectionOverlay { continuation.resume(returning: $0) }
            current = overlay
            overlay.show()
        }
    }

    private var windows: [NSWindow] = []
    private let completion: (Selection?) -> Void

    private init(completion: @escaping (Selection?) -> Void) {
        self.completion = completion
    }

    private func show() {
        let mouse = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            // Non-activating: the overlay takes keys and mouse without activating Quick Notes,
            // which would pull its note window in front of whatever is being captured.
            let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
            window.hidesOnDeactivate = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.contentView = SelectionView { [weak self] rect in
                self?.finish(rect.map {
                    Selection(displayID: screen.displayID, scale: screen.backingScaleFactor,
                              screenHeight: screen.frame.height, rect: $0)
                })
            }
            window.setFrame(screen.frame, display: false)
            windows.append(window)
            if screen.frame.contains(mouse) {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(window.contentView)
            } else {
                window.orderFrontRegardless()
            }
        }
        NSCursor.crosshair.set()
    }

    private func finish(_ selection: Selection?) {
        guard Self.current === self else { return }
        Self.current = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []
        completion(selection)
    }
}

private final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    private let onFinish: (CGRect?) -> Void
    private var start: NSPoint?
    private var selection: CGRect?

    init(onFinish: @escaping (CGRect?) -> Void) {
        self.onFinish = onFinish
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // Cursor rects only apply while Quick Notes is active, which it isn't during a capture.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.crosshair.set()
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(
            x: min(start.x, point.x), y: min(start.y, point.y),
            width: abs(point.x - start.x), height: abs(point.y - start.y)
        ).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        // A click or a tiny drag is almost certainly a mistake; treat it as cancel.
        if let selection, selection.width >= 4, selection.height >= 4 {
            onFinish(selection)
        } else {
            onFinish(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            onFinish(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        guard let selection else { return }
        NSColor.clear.setFill()
        selection.fill(using: .copy)
        NSColor.white.setStroke()
        NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
