import AppKit
import QuickNotesCore
import SwiftUI
import UniformTypeIdentifiers

/// Lets SwiftUI hand keyboard focus to the current editor, which is recreated per note.
@MainActor
final class EditorFocus {
    fileprivate weak var textView: NSTextView?

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }
}

/// Ruled-paper text editor: 32pt lines, text sitting on the rules, amber margin line.
struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let focus: EditorFocus

    static let lineHeight: CGFloat = 32
    static let textInset = NSSize(width: 76, height: 48)
    static let marginX: CGFloat = 56
    static let fontSize: CGFloat = 17

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = RuledTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = .clear
        textView.textColor = Palette.text
        textView.insertionPointColor = Palette.accent
        textView.textContainerInset = Self.textInset
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Self.lineHeight
        paragraph.maximumLineHeight = Self.lineHeight
        let font = Typeface.nsFont(size: Self.fontSize)
        // Center glyphs in each line so the baseline sits just above the rule.
        let baselineOffset = (Self.lineHeight - (font.ascender - font.descender)) / 2 - 4
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: Palette.text,
            .paragraphStyle: paragraph,
            .baselineOffset: baselineOffset,
        ]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.setText(text)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        textView.isEditable = isEditable
        focus.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? RuledTextView else { return }
        context.coordinator.text = $text
        textView.isEditable = isEditable
        if textView.string != text {
            textView.setText(text)
        }
        focus.textView = textView
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

private final class RuledTextView: NSTextView {
    /// Own undo stack so undo history never crosses notes.
    private let ownUndoManager = UndoManager()
    override var undoManager: UndoManager? { ownUndoManager }

    func setText(_ text: String) {
        textStorage?.setAttributedString(NSAttributedString(string: text, attributes: typingAttributes))
    }

    // MARK: Images → text

    private static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]

    /// Lets Paste enable, and drops land, when the pasteboard holds only an image.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + Self.imageTypes
    }

    override func paste(_ sender: Any?) {
        if !insertTextFromImage(on: .general) { super.paste(sender) }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isEditable, Self.hasImage(sender.draggingPasteboard) else {
            return super.performDragOperation(sender)
        }
        let point = convert(sender.draggingLocation, from: nil)
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
        return insertTextFromImage(on: sender.draggingPasteboard)
    }

    /// Screenshots, copied images, and image files paste as their recognized text.
    /// Returns false when the pasteboard holds text or no image, so normal handling applies.
    private func insertTextFromImage(on pboard: NSPasteboard) -> Bool {
        guard isEditable else { return false }
        if let url = Self.imageFileURL(on: pboard) {
            insertRecognizedText { try await TextRecognizer.recognizeText(at: url) }
            return true
        }
        guard pboard.string(forType: .string) == nil,
              let type = pboard.availableType(from: Self.imageTypes),
              let data = pboard.data(forType: type) else { return false }
        insertRecognizedText { try await TextRecognizer.recognizeText(in: data) }
        return true
    }

    private static func hasImage(_ pboard: NSPasteboard) -> Bool {
        imageFileURL(on: pboard) != nil
            || (pboard.string(forType: .string) == nil && pboard.availableType(from: imageTypes) != nil)
    }

    private static func imageFileURL(on pboard: NSPasteboard) -> URL? {
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]) as? [URL]
        return urls?.first
    }

    private func insertRecognizedText(_ recognize: @escaping @Sendable () async throws -> String) {
        Task { [weak self] in
            do {
                let text = try await recognize()
                // Insert at wherever the cursor is now; this is undoable like typing.
                guard let self, self.isEditable else { return }
                self.insertText(text, replacementRange: self.selectedRange())
            } catch {
                NSLog("QuickNotes: text recognition failed: \(error)")
                NSSound.beep()
            }
        }
    }

    /// Always at least as tall as the visible area, so the paper is ruled all the way down.
    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        if let visible = enclosingScrollView?.contentSize.height {
            size.height = max(size.height, visible)
        }
        super.setFrameSize(size)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        // Rules scroll with the text: one under each line, starting at the first line.
        Palette.rule.setFill()
        let lineHeight = NoteEditor.lineHeight
        let top = NoteEditor.textInset.height
        var y = top + lineHeight * max(0, ((rect.minY - top) / lineHeight).rounded(.down)) + lineHeight - 1
        while y <= rect.maxY {
            NSRect(x: rect.minX, y: y, width: rect.width, height: 1).fill()
            y += lineHeight
        }

        Palette.margin.setFill()
        NSRect(x: NoteEditor.marginX, y: rect.minY, width: 1, height: rect.height).fill(using: .sourceOver)
    }
}
