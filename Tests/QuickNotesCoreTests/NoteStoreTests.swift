import Foundation
import Testing
@testable import QuickNotesCore

@Suite struct NoteStoreTests {
    @Test func saveThenLoadRoundTrips() throws {
        let url = makeTempNotesURL()
        let store = NoteStore(fileURL: url)
        let notes = [
            Note(body: "one"),
            Note(body: "two\nlines"),
            Note(body: "three", created: Date(timeIntervalSince1970: 1000)),
        ]
        try store.save(notes)

        #expect(try NoteStore(fileURL: url).load() == notes)
    }

    @Test func missingFileLoadsEmptyWithoutCreatingFile() throws {
        let url = makeTempNotesURL()
        #expect(try NoteStore(fileURL: url).load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func saveCreatesMissingParentDirectory() throws {
        let url = makeTempNotesURL().deletingLastPathComponent()
            .appendingPathComponent("nested/deeper/notes.json")
        try NoteStore(fileURL: url).save([Note(body: "x")])
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func unusualTextRoundTrips() throws {
        let url = makeTempNotesURL()
        let long = String(repeating: "lorem ipsum ", count: 20_000)
        let notes = [Note(body: "emoji 🐸🎉\n\n\ttabs\r\nCRLF"), Note(body: long)]
        try NoteStore(fileURL: url).save(notes)
        #expect(try NoteStore(fileURL: url).load() == notes)
    }

    @Test func corruptFileIsMovedAsideAndPreserved() throws {
        let url = makeTempNotesURL()
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let garbage = Data("{not json".utf8)
        try garbage.write(to: url)

        #expect(try NoteStore(fileURL: url).load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))

        let aside = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("notes.corrupt-") }
        #expect(aside.count == 1)
        #expect(try Data(contentsOf: dir.appendingPathComponent(aside[0])) == garbage)
    }

    @Test func unreadableFileMakesStoreReadOnly() throws {
        let url = makeTempNotesURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("[]".utf8)
        try original.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }

        let store = NoteStore(fileURL: url)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(store.isReadOnly)

        #expect(throws: NoteStore.ReadOnlyError.self) { try store.save([Note(body: "must not be written")]) }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func firstSaveBacksUpExistingFile() throws {
        let url = makeTempNotesURL()
        let old = [Note(body: "old")]
        try NoteStore(fileURL: url).save(old)

        let store = NoteStore(fileURL: url)
        _ = try store.load()
        try store.save([Note(body: "new")])
        try store.save([Note(body: "newer")])

        let backup = try JSONDecoder().decode([Note].self, from: Data(contentsOf: store.backupURL))
        #expect(backup == old)
    }

    @Test func failedBackupDoesNotBlockSaveOrLoseOldBackup() throws {
        let url = makeTempNotesURL()
        try NoteStore(fileURL: url).save([Note(body: "older")])
        try NoteStore(fileURL: url).save([Note(body: "old")]) // .bak now holds "older"
        // Write-only notes file: the backup copy can't read it, but the atomic save still works.
        try FileManager.default.setAttributes([.posixPermissions: 0o200], ofItemAtPath: url.path)

        let store = NoteStore(fileURL: url)
        try store.save([Note(body: "new")])

        // Atomic writes keep the original permissions; restore read access to verify.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(try NoteStore(fileURL: url).load().map(\.body) == ["new"])
        let backup = try JSONDecoder().decode([Note].self, from: Data(contentsOf: store.backupURL))
        #expect(backup.map(\.body) == ["older"])
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            .filter { $0.hasPrefix(".notes.bak-") }
        #expect(leftovers.isEmpty)
    }

    @Test func corruptFileKeepsLastBackupAside() throws {
        let url = makeTempNotesURL()
        let good = [Note(body: "good")]
        try NoteStore(fileURL: url).save(good)
        let second = NoteStore(fileURL: url)
        try second.save(good) // creates .bak holding "good"
        try Data("garbage".utf8).write(to: url)

        let store = NoteStore(fileURL: url)
        #expect(try store.load().isEmpty)
        #expect(store.movedAsideURL != nil)

        let folder = url.deletingLastPathComponent()
        let keptBackup = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix("notes.corrupt-") && $0.hasSuffix(".bak") }
        #expect(keptBackup.count == 1)
        let kept = try JSONDecoder().decode([Note].self, from: Data(contentsOf: folder.appendingPathComponent(keptBackup[0])))
        #expect(kept == good)
    }

    // Covers AE4.
    @Test func notesSurviveNewStoreInstance() throws {
        let url = makeTempNotesURL()
        try NoteStore(fileURL: url).save([Note(body: "typed before quit")])
        #expect(try NoteStore(fileURL: url).load().map(\.body) == ["typed before quit"])
    }
}

@Suite struct NoteTests {
    // Covers AE5.
    @Test func titleIsFirstNonEmptyLine() {
        #expect(Note(body: "groceries\nmilk").title == "groceries")
        #expect(Note(body: "\n\n  todo").title == "todo")
        #expect(Note(body: "").title == nil)
        #expect(Note(body: "  \n\t").title == nil)
        #expect(Note(body: "").displayTitle == Note.placeholderTitle)
    }

    @Test func blankDetection() {
        #expect(Note(body: " \n\t ").isBlank)
        #expect(!Note(body: " x ").isBlank)
    }
}
