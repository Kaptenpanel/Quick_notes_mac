import QuickNotesCore
import SwiftUI

struct ContentView: View {
    let controller: NotesController
    @Bindable var pin: PinState

    @FocusState private var editorFocused: Bool
    @State private var noteAwaitingDelete: Note?

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                ForEach(controller.notes) { note in
                    NoteRow(title: note.displayTitle, modified: note.modified)
                        .tag(note.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) { requestDelete(note) }
                        }
                }
            }
            .onDeleteCommand(perform: deleteSelected)
            .navigationSplitViewColumnWidth(min: 160, ideal: 200)
        } detail: {
            VStack(spacing: 0) {
                if let problem = saveProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.red)
                }
                detail
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { controller.newNote() } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .help("New Note (⌘N)")
                .disabled(controller.isReadOnly)

                Button(action: deleteSelected) {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete Note")
                .disabled(controller.selectedNote == nil)

                Button { pin.isPinned.toggle() } label: {
                    Label(pin.isPinned ? "Unpin" : "Pin on Top",
                          systemImage: pin.isPinned ? "pin.fill" : "pin.slash")
                }
                .help(pin.isPinned ? "Floating above other windows — click to unpin"
                                   : "Not floating — click to keep on top")
            }
        }
        .onChange(of: controller.focusRequest) {
            // Wait a tick so a freshly created editor exists before focusing it.
            DispatchQueue.main.async { editorFocused = true }
        }
        .alert(
            "Delete this note?",
            isPresented: Binding(
                get: { noteAwaitingDelete != nil },
                set: { if !$0 { noteAwaitingDelete = nil } }
            ),
            presenting: noteAwaitingDelete
        ) { note in
            Button("Delete", role: .destructive) { controller.delete(note.id) }
            Button("Cancel", role: .cancel) {}
        } message: { note in
            Text("\"\(note.displayTitle)\" will be permanently deleted.")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let note = controller.selectedNote {
            TextEditor(text: bodyBinding(for: note.id))
                .font(.body)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .focused($editorFocused)
                .disabled(controller.isReadOnly)
                // Fresh editor per note so undo history never crosses notes.
                .id(note.id)
        } else {
            ContentUnavailableView {
                Label("No Note Selected", systemImage: "note.text")
            } description: {
                Text(controller.isReadOnly
                     ? "Editing is off because your notes file couldn't be read."
                     : "Press \(HotKeyConfig.display) from any app to start a note.")
            } actions: {
                Button("New Note") { controller.newNote() }
                    .disabled(controller.isReadOnly)
            }
        }
    }

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

    private var selection: Binding<UUID?> {
        Binding(get: { controller.selectedID }, set: { controller.select($0) })
    }

    private func bodyBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { controller.note(withID: id)?.body ?? "" },
            set: { controller.updateBody($0, for: id) }
        )
    }

    private func deleteSelected() {
        if let note = controller.selectedNote { requestDelete(note) }
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

private struct NoteRow: View {
    let title: String
    let modified: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).lineLimit(1)
            Text(modified, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
