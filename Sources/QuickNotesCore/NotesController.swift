import Foundation
import Observation

/// Runs `fire` later. Used to debounce saves; tests inject a manual scheduler.
public typealias SaveScheduler = @MainActor (_ fire: @escaping @MainActor () -> Void) -> Void

/// Owns the note list, selection, and every note behavior. UI-free.
///
/// Blank notes are scratch space: they're reused by `newNote`, discarded when
/// the user leaves them, and never written to disk.
@MainActor
@Observable
public final class NotesController {
    /// Pinned first, then newest-created first.
    public private(set) var notes: [Note] = []
    public private(set) var selectedID: UUID?
    /// Incremented whenever the editor should take keyboard focus.
    public private(set) var focusRequest = 0
    public private(set) var loadError: Error?
    /// Set when the notes file couldn't be read. Editing is disabled so nothing
    /// is typed that can't be saved.
    public let isReadOnly: Bool
    /// Where an undecodable notes file was moved at launch, if that happened.
    public let recoveredFileURL: URL?
    /// Description of the most recent save failure; nil once a save succeeds.
    public private(set) var saveError: String?
    /// True when edits exist that haven't reached disk.
    public private(set) var hasUnsavedChanges = false

    @ObservationIgnored private let store: NoteStore
    @ObservationIgnored private let scheduleSave: SaveScheduler
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var editGeneration = 0
    @ObservationIgnored var savesPerformed = 0

    public init(
        store: NoteStore,
        scheduleSave: @escaping SaveScheduler = NotesController.debouncedScheduler(),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.scheduleSave = scheduleSave
        self.now = now
        do {
            notes = try store.load().sorted(by: Self.listOrder)
        } catch {
            loadError = error
        }
        isReadOnly = store.isReadOnly
        recoveredFileURL = store.movedAsideURL
        selectedID = mostRecentlyEditedID
    }

    public static func debouncedScheduler(delay: TimeInterval = 0.5) -> SaveScheduler {
        { fire in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { fire() }
            }
        }
    }

    public var selectedNote: Note? {
        selectedID.flatMap(note(withID:))
    }

    // MARK: Actions

    /// Hotkey and New button: reuse the newest blank note if one exists, otherwise create one.
    public func newNote() {
        guard !isReadOnly else { return }
        if let blank = notes.first(where: \.isBlank) {
            select(blank.id)
        } else {
            let stamp = now()
            let note = Note(created: stamp, modified: stamp)
            notes.insert(note, at: notes.firstIndex { !$0.pinned } ?? notes.endIndex)
            selectedID = note.id
        }
        focusRequest += 1
    }

    /// Screen capture: a new note that starts with `body` (reusing a blank note if one exists).
    public func newNote(body: String) {
        guard !isReadOnly else { return }
        newNote()
        if let selectedID { updateBody(body, for: selectedID) }
    }

    /// Selecting away from a blank note discards it.
    public func select(_ id: UUID?) {
        guard id != selectedID else { return }
        let previous = selectedID
        selectedID = id
        if let previous { discardIfBlank(previous) }
    }

    public func updateBody(_ body: String, for id: UUID) {
        guard !isReadOnly, let index = index(of: id), notes[index].body != body else { return }
        notes[index].body = body
        notes[index].modified = now()
        scheduleDebouncedSave()
    }

    /// Moves the note into or out of the pinned group at the top of the list.
    public func togglePin(_ id: UUID) {
        guard !isReadOnly, let index = index(of: id) else { return }
        notes[index].pinned.toggle()
        notes.sort(by: Self.listOrder)
        saveNow()
    }

    public func delete(_ id: UUID) {
        guard !isReadOnly, let index = index(of: id) else { return }
        notes.remove(at: index)
        if selectedID == id {
            selectedID = notes.indices.contains(index) ? notes[index].id : notes.last?.id
        }
        saveNow()
    }

    /// Called before the window hides: drop a blank selected note and persist.
    public func windowWillHide() {
        if let selectedID, discardIfBlank(selectedID) {
            self.selectedID = mostRecentlyEditedID
        }
        flush()
    }

    /// Saves immediately if anything is unsaved.
    public func flush() {
        if hasUnsavedChanges { saveNow() }
    }

    // MARK: Private

    private static func listOrder(_ a: Note, _ b: Note) -> Bool {
        a.pinned != b.pinned ? a.pinned : a.created > b.created
    }

    private var mostRecentlyEditedID: UUID? {
        notes.max { $0.modified < $1.modified }?.id
    }

    private func index(of id: UUID) -> Int? {
        notes.firstIndex { $0.id == id }
    }

    public func note(withID id: UUID) -> Note? {
        index(of: id).map { notes[$0] }
    }

    @discardableResult
    private func discardIfBlank(_ id: UUID) -> Bool {
        guard let index = index(of: id), notes[index].isBlank else { return false }
        notes.remove(at: index)
        return true
    }

    private func scheduleDebouncedSave() {
        hasUnsavedChanges = true
        editGeneration += 1
        let generation = editGeneration
        scheduleSave { [weak self] in
            guard let self, generation == self.editGeneration else { return }
            self.flush()
        }
    }

    private func saveNow() {
        do {
            try store.save(notes.filter { !$0.isBlank })
            hasUnsavedChanges = false
            saveError = nil
            savesPerformed += 1
        } catch {
            saveError = error.localizedDescription
            NSLog("QuickNotes: save failed: \(error)")
            // Keep retrying on the debounce timer instead of waiting for another keystroke.
            scheduleDebouncedSave()
        }
    }
}
