import AppKit
import SwiftUI

/// Plain-text editor drawn like ruled notebook paper: a rule under every line and a
/// margin line, both scrolling with the text. SwiftUI's TextEditor can't draw per-line.
struct RuledTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    /// Set true to make the editor first responder; it resets itself once focused.
    @Binding var focusRequested: Bool

    static let font = Theme.monoNSFont(15)
    static let lineSpacing: CGFloat = 6
    static let marginX: CGFloat = 55
    /// Text starts ~20pt right of the margin line.
    static let textInset = NSSize(width: marginX + 20, height: 36)
    static let trailingInset: CGFloat = 16

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = RuledTextView()
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = Self.lineSpacing
        paragraph.firstLineHeadIndent = Self.textInset.width
        paragraph.headIndent = Self.textInset.width
        paragraph.tailIndent = -Self.trailingInset

        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: Self.textInset.height)
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = Self.font
        textView.textColor = NSColor(Theme.ink)
        textView.insertionPointColor = NSColor(Theme.ink)
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: Self.font,
            .foregroundColor: NSColor(Theme.ink),
            .paragraphStyle: paragraph,
        ]
        textView.string = text
        textView.textStorage?.setAttributes(textView.typingAttributes, range: NSRange(location: 0, length: (text as NSString).length))
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? RuledTextView else { return }
        context.coordinator.text = $text
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEditable
        if focusRequested {
            // The view may not be in a window yet on the pass that creates it.
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                focusRequested = false
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

final class RuledTextView: NSTextView {
    private var lineHeight: CGFloat {
        NSLayoutManager().defaultLineHeight(for: RuledTextEditor.font) + RuledTextEditor.lineSpacing
    }

    // Fill the visible area even when the text is short, so rules reach the bottom.
    override func setFrameSize(_ newSize: NSSize) {
        let minHeight = enclosingScrollView?.contentSize.height ?? 0
        super.setFrameSize(NSSize(width: newSize.width, height: max(newSize.height, minHeight)))
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.rule.setFill()
        let top = textContainerInset.height
        let first = max(0, Int(((dirtyRect.minY - top) / lineHeight).rounded(.down)))
        var row = first
        while true {
            // Sit each rule in the gap below the line's descenders.
            let y = top + CGFloat(row + 1) * lineHeight - RuledTextEditor.lineSpacing / 2
            if y > dirtyRect.maxY { break }
            NSRect(x: dirtyRect.minX, y: y.rounded(.down), width: dirtyRect.width, height: 1).fill()
            row += 1
        }

        NSColor(Theme.accent).setFill()
        NSRect(x: RuledTextEditor.marginX, y: dirtyRect.minY, width: 2, height: dirtyRect.height).fill()

        super.draw(dirtyRect)
    }
}
