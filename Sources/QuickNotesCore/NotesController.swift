import Foundation
import Observation

/// Runs `fire` later. Used to debounce saves; tests inject a manual scheduler.
public typealias SaveScheduler = @MainActor (_ fire: @escaping @MainActor () -> Void) -> Void

/// Owns the note list, selection, and every note behavior. UI-free.
@MainActor
@Observable
public final class NotesController {
    /// Newest-created first.
    public private(set) var notes: [Note] = []
    public private(set) var selectedID: UUID?
    /// Incremented whenever the editor should take keyboard focus.
    public private(set) var focusRequest = 0
    public private(set) var loadError: Error?

    @ObservationIgnored private let store: NoteStore
    @ObservationIgnored private let scheduleSave: SaveScheduler
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var editGeneration = 0
    @ObservationIgnored private var hasPendingSave = false
    @ObservationIgnored var savesPerformed = 0

    public static let defaultDebounce: TimeInterval = 0.5

    public init(
        store: NoteStore,
        scheduleSave: @escaping SaveScheduler = NotesController.debouncedScheduler(),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.scheduleSave = scheduleSave
        self.now = now
        do {
            notes = try store.load().sorted { $0.created > $1.created }
        } catch {
            loadError = error
        }
        selectedID = notes.max { $0.modified < $1.modified }?.id
    }

    public static func debouncedScheduler(delay: TimeInterval = defaultDebounce) -> SaveScheduler {
        { fire in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { fire() }
            }
        }
    }

    // MARK: Reading

    public var selectedNote: Note? {
        guard let selectedID else { return nil }
        return notes.first { $0.id == selectedID }
    }

    public static let placeholderTitle = "New Note"

    public func title(for note: Note) -> String {
        note.title ?? Self.placeholderTitle
    }

    // MARK: Actions

    /// Hotkey and New button: reuse the newest blank note if one exists, otherwise create one.
    public func newNote() {
        if let blank = notes.first(where: \.isBlank) {
            select(blank.id)
        } else {
            let stamp = now()
            let note = Note(created: stamp, modified: stamp)
            notes.insert(note, at: 0)
            selectedID = note.id
            scheduleDebouncedSave()
        }
        focusRequest += 1
    }

    /// Selecting away from a blank note discards it.
    public func select(_ id: UUID?) {
        guard id != selectedID else { return }
        let previous = selectedID
        selectedID = id
        if let previous { discardIfBlank(previous) }
    }

    public func updateBody(_ body: String, for id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }),
              notes[index].body != body else { return }
        notes[index].body = body
        notes[index].modified = now()
        scheduleDebouncedSave()
    }

    public func delete(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes.remove(at: index)
        if selectedID == id {
            if notes.indices.contains(index) {
                selectedID = notes[index].id
            } else {
                selectedID = notes.last?.id
            }
        }
        saveNow()
    }

    /// Called before the window hides: drop a blank selected note and persist.
    public func windowWillHide() {
        if let selectedID, selectedNote?.isBlank == true {
            notes.removeAll { $0.id == selectedID }
            self.selectedID = notes.max { $0.modified < $1.modified }?.id
            hasPendingSave = true
        }
        flush()
    }

    /// Saves immediately if anything is unsaved.
    public func flush() {
        if hasPendingSave { saveNow() }
    }

    // MARK: Private

    private func discardIfBlank(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].isBlank else { return }
        notes.remove(at: index)
        scheduleDebouncedSave()
    }

    private func scheduleDebouncedSave() {
        hasPendingSave = true
        editGeneration += 1
        let generation = editGeneration
        scheduleSave { [weak self] in
            guard let self, generation == self.editGeneration else { return }
            self.flush()
        }
    }

    private func saveNow() {
        hasPendingSave = false
        do {
            try store.save(notes)
            savesPerformed += 1
        } catch {
            // Keep the pending flag so the next edit or flush retries.
            hasPendingSave = true
            NSLog("QuickNotes: save failed: \(error)")
        }
    }
}
