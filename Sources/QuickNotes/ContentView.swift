import AppKit
import QuickNotesCore
import SwiftUI

struct ContentView: View {
    let controller: NotesController
    let pin: PinState

    @State private var query = ""
    @State private var editorFocus = EditorFocus()
    @State private var noteAwaitingDelete: Note?

    var body: some View {
        VStack(spacing: 0) {
            TitleBar()
            if let problem = saveProblem {
                SaveBanner(message: problem)
            }
            HStack(spacing: 0) {
                sidebar
                editorPanel
            }
        }
        .background(Palette.windowBackground.color)
        .ignoresSafeArea(edges: .top)
        .onChange(of: controller.focusRequest) {
            query = ""
            // Wait a tick so a freshly created editor exists before focusing it.
            DispatchQueue.main.async { editorFocus.focus() }
        }
        .alert(
            "Delete this note?",
            isPresented: isConfirmingDelete,
            presenting: noteAwaitingDelete
        ) { note in
            Button("Delete", role: .destructive) { controller.delete(note.id) }
            Button("Cancel", role: .cancel) {}
        } message: { note in
            Text("\"\(note.displayTitle)\" will be permanently deleted.")
        }
    }

    // MARK: Sidebar

    // Split into small pieces: one big nested builder here cost ~1s of type-checking per build.
    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader
            ScrollView { noteList }
                .scrollIndicators(.automatic)
        }
        .frame(width: 280)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            SearchField(text: $query)
            AddButton { controller.newNote() }
                .disabled(controller.isReadOnly)
        }
        // The + button matches the search field's height instead of growing.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    private var noteList: some View {
        let notes: [Note] = shownNotes
        return LazyVStack(spacing: 3) {
            ForEach(notes) { (note: Note) in row(for: note) }
            if notes.isEmpty && !query.isEmpty { NothingFound() }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
    }

    private func row(for note: Note) -> some View {
        NoteRow(note: note, isSelected: note.id == controller.selectedID)
            .onTapGesture { controller.select(note.id) }
            .contextMenu {
                Button(note.pinned ? "Unpin" : "Pin to Top") { controller.togglePin(note.id) }
                Button("Delete", role: .destructive) { requestDelete(note) }
            }
    }

    private var shownNotes: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return controller.notes }
        return controller.notes.filter { $0.body.localizedCaseInsensitiveContains(q) }
    }

    // MARK: Editor

    private var editorPanel: some View {
        ZStack(alignment: .topTrailing) {
            if let note = controller.selectedNote {
                NoteEditor(text: bodyBinding(for: note.id), isEditable: !controller.isReadOnly, focus: editorFocus)
                    // Fresh editor per note so undo history never crosses notes.
                    .id(note.id)
                if note.body.isEmpty {
                    EditorPlaceholder()
                }
                noteActions(for: note)
            } else {
                emptyEditor
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.editorBackground.color)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12))
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 12)
                .stroke(Palette.editorBorder.color, lineWidth: 1)
        )
        // Push the right and bottom border just past the window edge; only top and left show.
        .padding([.trailing, .bottom], -1)
    }

    private func noteActions(for note: Note) -> some View {
        HStack(spacing: 2) {
            ActionButton(title: pin.isPinned ? "Unpin" : "Pin", hoverColor: Palette.text) {
                pin.isPinned.toggle()
            }
            .help(pin.isPinned ? "Stop keeping the window above other apps"
                               : "Keep the window above other apps")
            ActionButton(title: "Delete", hoverColor: Palette.destructive) { requestDelete(note) }
                .help("Delete note")
                .disabled(controller.isReadOnly)
        }
        .padding(.top, 12)
        .padding(.trailing, 14)
    }

    private var emptyEditor: some View {
        VStack(spacing: 14) {
            Text(controller.isReadOnly
                 ? "Editing is off because your notes file couldn't be read."
                 : "Press \(HotKeyConfig.display) from any app to start a note.")
                .font(Typeface.font(size: 15))
                .foregroundStyle(Palette.secondaryText.color)
                .multilineTextAlignment(.center)
            ActionButton(title: "New note", hoverColor: Palette.text) { controller.newNote() }
                .disabled(controller.isReadOnly)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    /// Shown as a banner whenever typing might not reach disk.
    private var saveProblem: String? {
        if controller.isReadOnly {
            return "Notes file couldn't be read — editing is off to protect it."
        }
        if let error = controller.saveError {
            return "Not saved: \(error) Retrying…"
        }
        return nil
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(
            get: { noteAwaitingDelete != nil },
            set: { if !$0 { noteAwaitingDelete = nil } }
        )
    }

    private func bodyBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { controller.note(withID: id)?.body ?? "" },
            set: { controller.updateBody($0, for: id) }
        )
    }

    /// Notes with text ask first; blank notes go immediately.
    private func requestDelete(_ note: Note) {
        if note.isBlank {
            controller.delete(note.id)
        } else {
            noteAwaitingDelete = note
        }
    }
}

// MARK: - Pieces

private struct SaveBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(Typeface.font(size: 13))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Palette.destructive.color)
    }
}

private struct NothingFound: View {
    var body: some View {
        Text("Nothing found.")
            .font(Typeface.font(size: 15))
            .foregroundStyle(Palette.secondaryText.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
    }
}

private struct EditorPlaceholder: View {
    var body: some View {
        Text("Start typing…")
            .font(Typeface.font(size: NoteEditor.fontSize))
            .foregroundStyle(Palette.placeholder.color)
            .padding(.leading, NoteEditor.textInset.width)
            .padding(.top, NoteEditor.textInset.height + 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
    }
}

private struct TitleBar: View {
    var body: some View {
        Text("QuickNotes\(Text(".").foregroundColor(Palette.accent.color))")
            .font(Typeface.font(size: 14, bold: true))
            .tracking(0.3)
            .foregroundStyle(Palette.titleText.color)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(WindowDragArea())
    }
}

/// The content covers the title bar, so this strip moves the window instead.
private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct SearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Search", text: $text, prompt: Text("Search").foregroundColor(Palette.placeholder.color))
            .textFieldStyle(.plain)
            .font(Typeface.font(size: 15))
            .foregroundStyle(Palette.text.color)
            .focused($focused)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Palette.fieldBackground.color, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke((focused ? Palette.fieldBorderFocused : Palette.fieldBorder).color, lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.2), value: focused)
    }
}

private struct AddButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("+")
                .font(Typeface.font(size: 19, bold: true))
                .foregroundStyle((hovering ? Palette.addButtonHoverText : Palette.text).color)
                .frame(width: 38)
                .frame(maxHeight: .infinity)
                .background(
                    (hovering ? Palette.addButtonHover : Palette.addButton).color,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: hovering)
        .help("New note (⌘N)")
    }
}

private struct ActionButton: View {
    let title: String
    let hoverColor: NSColor
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typeface.font(size: 13))
                .foregroundStyle((hovering ? hoverColor : Palette.secondaryText).color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    hovering ? Palette.actionHover.color : .clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: hovering)
    }
}

private struct NoteRow: View {
    let note: Note
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(note.displayTitle)
                .font(Typeface.font(size: 15, bold: isSelected))
                .foregroundStyle((isSelected ? Palette.rowSelectedText : Palette.row).color)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(note.modified, format: .dateTime.month(.abbreviated).day())
                .font(Typeface.font(size: 12))
                .foregroundStyle((isSelected ? Palette.rowDateSelected : Palette.rowDate).color)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            isSelected ? Palette.rowSelected.color : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(alignment: .topTrailing) {
            if note.pinned {
                Circle()
                    .fill(Palette.accent.color)
                    .frame(width: 5, height: 5)
                    .padding(.top, 8)
                    .padding(.trailing, 6)
            }
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.2), value: isSelected)
    }
}
