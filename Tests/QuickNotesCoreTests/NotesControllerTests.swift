import Foundation
import Testing
@testable import QuickNotesCore

/// Collects scheduled saves so tests decide when they fire.
@MainActor
private final class ManualScheduler {
    var pending: [@MainActor () -> Void] = []
    var schedule: SaveScheduler {
        { fire in self.pending.append(fire) }
    }
    func fireAll() {
        let fires = pending
        pending.removeAll()
        fires.forEach { $0() }
    }
}

/// Monotonic fake clock: each call advances one second.
private final class Clock: @unchecked Sendable {
    private var t: TimeInterval = 1_000_000
    func now() -> Date { t += 1; return Date(timeIntervalSince1970: t) }
}

@MainActor
private func makeController(
    seed: [Note] = [],
    scheduler: ManualScheduler = ManualScheduler()
) throws -> (NotesController, NoteStore, ManualScheduler) {
    let url = makeTempNotesURL()
    let store = NoteStore(fileURL: url)
    if !seed.isEmpty { try store.save(seed) }
    let clock = Clock()
    let controller = NotesController(
        store: store,
        scheduleSave: scheduler.schedule,
        now: clock.now
    )
    return (controller, store, scheduler)
}

@MainActor
@Suite struct NotesControllerTests {
    @Test func newNotesListNewestFirst() throws {
        let (c, _, _) = try makeController()
        c.newNote()
        c.updateBody("first", for: c.selectedID!)
        c.newNote()
        c.updateBody("second", for: c.selectedID!)
        #expect(c.notes.map(\.body) == ["second", "first"])
    }

    @Test func selectingShowsThatNote() throws {
        let a = Note(body: "A", created: Date(timeIntervalSince1970: 1))
        let b = Note(body: "B", created: Date(timeIntervalSince1970: 2))
        let (c, _, _) = try makeController(seed: [a, b])
        c.select(b.id)
        #expect(c.selectedNote?.body == "B")
        c.select(a.id)
        #expect(c.selectedNote?.body == "A")
    }

    @Test func newNoteReusesSelectedBlankNote() throws {
        let (c, _, _) = try makeController()
        c.newNote()
        let first = c.selectedID
        c.newNote()
        #expect(c.notes.count == 1)
        #expect(c.selectedID == first)
    }

    @Test func newNoteReusesUnselectedBlankNote() throws {
        let blank = Note(body: "", created: Date(timeIntervalSince1970: 5))
        let full = Note(body: "text", created: Date(timeIntervalSince1970: 1), modified: Date(timeIntervalSince1970: 9))
        let (c, _, _) = try makeController(seed: [blank, full])
        #expect(c.selectedID == full.id)
        c.newNote()
        #expect(c.notes.count == 2)
        #expect(c.selectedID == blank.id)
    }

    @Test func newNoteCreatesWhenAllNotesHaveText() throws {
        let (c, _, _) = try makeController(seed: [Note(body: "x")])
        c.newNote()
        #expect(c.notes.count == 2)
        #expect(c.notes.first?.id == c.selectedID)
        #expect(c.selectedNote?.isBlank == true)
    }

    @Test func newNoteWithNoNotesCreatesOne() throws {
        let (c, _, _) = try makeController()
        #expect(c.selectedID == nil)
        c.newNote()
        #expect(c.notes.count == 1)
        #expect(c.selectedID == c.notes[0].id)
    }

    @Test func newNoteAlwaysRequestsFocus() throws {
        let (c, _, _) = try makeController()
        c.newNote()
        c.newNote()
        #expect(c.focusRequest == 2)
    }

    @Test func selectingAwayDiscardsBlankNote() throws {
        let (c, _, _) = try makeController(seed: [Note(body: "keep")])
        let keep = c.notes[0].id
        c.newNote()
        c.select(keep)
        #expect(c.notes.map(\.id) == [keep])
    }

    @Test func hidingDiscardsSelectedBlankNote() throws {
        let (c, store, _) = try makeController(seed: [Note(body: "keep")])
        c.newNote()
        c.windowWillHide()
        #expect(c.notes.map(\.body) == ["keep"])
        #expect(c.selectedNote?.body == "keep")
        #expect(try store.load().map(\.body) == ["keep"])
    }

    @Test func deleteSelectsNextThenPreviousThenNil() throws {
        let seed = (1...3).map { Note(body: "n\($0)", created: Date(timeIntervalSince1970: TimeInterval($0))) }
        let (c, store, _) = try makeController(seed: seed)
        #expect(c.notes.map(\.body) == ["n3", "n2", "n1"])

        c.select(c.notes[1].id)
        c.delete(c.notes[1].id)
        #expect(c.selectedNote?.body == "n1")

        c.delete(c.selectedID!)
        #expect(c.selectedNote?.body == "n3")

        c.delete(c.selectedID!)
        #expect(c.selectedID == nil)
        #expect(c.notes.isEmpty)
        #expect(try store.load().isEmpty)
    }

    @Test func loadSelectsMostRecentlyEdited() throws {
        let older = Note(body: "old edit", created: Date(timeIntervalSince1970: 10), modified: Date(timeIntervalSince1970: 10))
        let recent = Note(body: "recent edit", created: Date(timeIntervalSince1970: 1), modified: Date(timeIntervalSince1970: 50))
        let (c, _, _) = try makeController(seed: [older, recent])
        #expect(c.selectedID == recent.id)
    }

    @Test func flushPersistsEdits() throws {
        let (c, store, _) = try makeController()
        c.newNote()
        c.updateBody("typed", for: c.selectedID!)
        c.flush()
        #expect(try store.load().map(\.body) == ["typed"])
    }

    @Test func rapidEditsSaveOnce() throws {
        let (c, store, scheduler) = try makeController()
        c.newNote()
        let id = c.selectedID!
        for text in ["h", "he", "hel", "hell", "hello"] { c.updateBody(text, for: id) }
        let before = c.savesPerformed
        scheduler.fireAll()
        #expect(c.savesPerformed == before + 1)
        #expect(try store.load().map(\.body) == ["hello"])
    }

    @Test func blankNotesAreNeverSaved() throws {
        let (c, store, _) = try makeController(seed: [Note(body: "keep")])
        c.newNote()
        c.delete(c.notes[1].id)
        #expect(c.selectedNote?.isBlank == true)
        #expect(try store.load().isEmpty)
    }

    @Test func editingDoesNotReorder() throws {
        let seed = (1...3).map { Note(body: "n\($0)", created: Date(timeIntervalSince1970: TimeInterval($0))) }
        let (c, _, _) = try makeController(seed: seed)
        let order = c.notes.map(\.id)
        c.updateBody("changed", for: c.notes[2].id)
        #expect(c.notes.map(\.id) == order)
    }
}
