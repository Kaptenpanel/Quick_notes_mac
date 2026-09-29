import Testing
@testable import QuickNotesCore

@Suite struct NoteSearchTests {
    @Test func emptyOrWhitespaceQueryMatchesEverything() {
        let note = Note(body: "Groceries")
        #expect(note.matches(""))
        #expect(note.matches("   \n"))
        #expect(Note(body: "").matches(""))
    }

    @Test func matchesIgnoringCaseAndAccents() {
        let note = Note(body: "Café list\n- rye bread")
        #expect(note.matches("cafe"))
        #expect(note.matches("CAFÉ"))
        #expect(note.matches("RYE"))
    }

    @Test func trimsQueryAndSearchesWholeBody() {
        let note = Note(body: "Groceries\n- coffee beans")
        #expect(note.matches("  coffee "))
        #expect(!note.matches("tea"))
    }
}
