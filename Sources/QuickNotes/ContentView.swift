import QuickNotesCore
import SwiftUI

struct ContentView: View {
    let controller: NotesController
    @Bindable var pin: PinState

    @State private var editorFocusRequested = false
    @FocusState private var listFocused: Bool
    @State private var noteAwaitingDelete: Note?
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 230)
                    .background(Theme.chrome)
                Theme.divider.frame(width: 1)
                editorPane
            }
        }
        // The header sits in the transparent titlebar, beside the traffic lights.
        .ignoresSafeArea(.container, edges: .top)
        .background(Theme.chrome)
        .foregroundStyle(Theme.ink)
        .onChange(of: controller.focusRequest) {
            // A new note must be visible, so drop any filter hiding it.
            search = ""
            editorFocusRequested = true
        }
        .alert(
            "Delete this note?",
            isPresented: Binding(
                get: { noteAwaitingDelete != nil },
                set: { if !$0 { noteAwaitingDelete = nil } }
            ),
            presenting: noteAwaitingDelete
        ) { note in
            Button("Delete", role: .destructive) { delete(note) }
            Button("Cancel", role: .cancel) {}
        } message: { note in
            Text("\"\(note.displayTitle)\" will be permanently deleted.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            (Text("QuickNotes") + Text(".").foregroundColor(Theme.accent))
                .font(Theme.mono(13, bold: true))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("QuickNotes")
            Theme.divider.frame(height: 1)
        }
        .frame(height: 29)
        .background(Theme.chrome)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                TextField("Search", text: $search, prompt: Text("Search").foregroundColor(Theme.muted))
                    .textFieldStyle(.plain)
                    .font(Theme.mono(13))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Theme.paper)
                    .overlay(Rectangle().strokeBorder(Theme.fieldBorder, lineWidth: 1))

                Button { controller.newNote() } label: {
                    Text("+")
                        .font(Theme.mono(18, bold: true))
                        .foregroundStyle(Theme.buttonText)
                        .frame(width: 28, height: 28)
                        .background(Theme.buttonFill)
                }
                .buttonStyle(.plain)
                .help("New Note (⌘N)")
                .accessibilityLabel("New Note")
                .disabled(controller.isReadOnly)
            }
            .padding([.horizontal, .top], 12)

            noteList
        }
    }

    private var noteList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(visibleNotes) { note in
                        NoteRow(note: note, isSelected: note.id == controller.selectedID)
                            .id(note.id)
                            .onTapGesture {
                                controller.select(note.id)
                                listFocused = true
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) { requestDelete(note) }
                                    .disabled(controller.isReadOnly)
                            }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onKeyPress(keys: [.upArrow, .downArrow, .delete, .deleteForward]) { press in
                switch press.key {
                case .upArrow: moveSelection(by: -1)
                case .downArrow: moveSelection(by: 1)
                default: deleteSelectedIfVisible()
                }
                return .handled
            }
            .onChange(of: controller.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private var visibleNotes: [Note] {
        controller.notes.filter { $0.matches(search) }
    }

    // MARK: Editor

    private var editorPane: some View {
        VStack(spacing: 0) {
            if let problem = saveProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.mono(12))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.red)
            }
            editor
        }
        .background(Theme.paper)
    }

    @ViewBuilder
    private var editor: some View {
        if let note = controller.selectedNote {
            ZStack(alignment: .topTrailing) {
                RuledTextEditor(
                    text: bodyBinding(for: note.id),
                    isEditable: !controller.isReadOnly,
                    focusRequested: $editorFocusRequested
                )
                // Fresh editor per note so undo history never crosses notes.
                .id(note.id)

                editorActions
            }
        } else {
            ContentUnavailableView {
                Label("No Note Selected", systemImage: "note.text")
                    .font(Theme.mono(17, bold: true))
            } description: {
                Text(controller.isReadOnly
                     ? "Editing is off because your notes file couldn't be read."
                     : "Press \(HotKeyConfig.display) from any app to start a note.")
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.muted)
            } actions: {
                Button("New Note") { controller.newNote() }
                    .font(Theme.mono(13))
                    .disabled(controller.isReadOnly)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var editorActions: some View {
        HStack(spacing: 14) {
            Button { pin.isPinned.toggle() } label: {
                Image(systemName: pin.isPinned ? "pin.fill" : "pin.slash")
            }
            .help(pin.isPinned ? "Floating above other windows — click to unpin"
                               : "Not floating — click to keep on top")
            .accessibilityLabel(pin.isPinned ? "Unpin" : "Pin on Top")

            Button(action: deleteSelected) {
                Image(systemName: "trash")
            }
            .help("Delete Note")
            .accessibilityLabel("Delete Note")
            .disabled(controller.selectedNote == nil || controller.isReadOnly)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.muted)
        .font(.system(size: 13))
        .padding(.top, 12)
        .padding(.trailing, 16)
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

    private func bodyBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { controller.note(withID: id)?.body ?? "" },
            set: { controller.updateBody($0, for: id) }
        )
    }

    /// Arrow keys step through the filtered list; a hidden selection jumps to its ends.
    private func moveSelection(by offset: Int) {
        let ids = visibleNotes.map(\.id)
        guard !ids.isEmpty else { return }
        if let current = controller.selectedID, let index = ids.firstIndex(of: current) {
            controller.select(ids[min(max(index + offset, 0), ids.count - 1)])
        } else {
            controller.select(offset > 0 ? ids.first : ids.last)
        }
    }

    private func deleteSelected() {
        if let note = controller.selectedNote { requestDelete(note) }
    }

    /// The list only deletes what it shows; a filter may hide the selection.
    private func deleteSelectedIfVisible() {
        guard let note = controller.selectedNote, visibleNotes.contains(where: { $0.id == note.id }) else { return }
        requestDelete(note)
    }

    /// Notes with text ask first; blank notes go immediately.
    private func requestDelete(_ note: Note) {
        guard !controller.isReadOnly else { return }
        if note.isBlank {
            delete(note)
        } else {
            noteAwaitingDelete = note
        }
    }

    /// While filtering, the next selection comes from the visible list, not the full one.
    private func delete(_ note: Note) {
        let visible = visibleNotes.map(\.id)
        let neighbour = visible.firstIndex(of: note.id).flatMap { index in
            visible.indices.contains(index + 1) ? visible[index + 1] : (index > 0 ? visible[index - 1] : nil)
        }
        controller.delete(note.id)
        guard !search.isEmpty, let selected = controller.selectedID,
              !visibleNotes.contains(where: { $0.id == selected }) else { return }
        controller.select(neighbour)
    }
}

private struct NoteRow: View {
    let note: Note
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(note.displayTitle)
                .font(Theme.mono(13, bold: true))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(note.modified, format: .dateTime.month(.abbreviated).day())
                .font(Theme.mono(11))
                .foregroundStyle(isSelected ? Theme.rowSelectedText.opacity(0.75) : Theme.muted)
                .fixedSize()
        }
        .foregroundStyle(isSelected ? Theme.rowSelectedText : Theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(isSelected ? Theme.rowSelected : .clear)
        .overlay(alignment: .leading) {
            if isSelected { Theme.accent.frame(width: 4) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
