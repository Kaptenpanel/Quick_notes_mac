import Foundation

/// Reads and writes all notes as one JSON file.
///
/// Safety rules:
/// - Missing file loads as an empty list.
/// - Undecodable file is moved aside (never overwritten) and loads as empty; the
///   existing `.bak` is preserved next to it so later backups can't replace it.
/// - Any other load failure leaves the file alone and makes the store read-only
///   for its lifetime, so a bad load can never be saved over real notes.
/// - The first save of each store instance copies the existing file to `.bak`
///   (best effort: a failed backup never blocks saving).
public final class NoteStore {
    public struct ReadOnlyError: Error {}

    public let fileURL: URL
    public private(set) var isReadOnly = false
    /// Where an undecodable notes file was moved during `load()`, if that happened.
    public private(set) var movedAsideURL: URL?
    private var didPrepareFirstSave = false
    private let fileManager = FileManager.default

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "QuickNotes/notes.json")
    }

    public var backupURL: URL {
        fileURL.appendingPathExtension("bak")
    }

    public func load() throws -> [Note] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            guard let notes = try? JSONDecoder().decode([Note].self, from: data) else {
                try moveCorruptFileAside()
                return []
            }
            return notes
        } catch {
            isReadOnly = true
            throw error
        }
    }

    public func save(_ notes: [Note]) throws {
        guard !isReadOnly else { throw ReadOnlyError() }

        if !didPrepareFirstSave {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            backUpExistingFile()
            didPrepareFirstSave = true
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(notes).write(to: fileURL, options: .atomic)
    }

    /// Copies to a temp file first, then swaps it in, so the old `.bak` survives a failed copy.
    private func backUpExistingFile() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let temp = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".notes.bak-\(UUID().uuidString)")
        do {
            try fileManager.copyItem(at: fileURL, to: temp)
            _ = try fileManager.replaceItemAt(backupURL, withItemAt: temp)
        } catch {
            try? fileManager.removeItem(at: temp)
            NSLog("QuickNotes: backup failed, saving anyway: \(error)")
        }
    }

    private func moveCorruptFileAside() throws {
        let stamp = Date.now.formatted(.iso8601.timeSeparator(.omitted))
        let folder = fileURL.deletingLastPathComponent()
        let aside = folder.appendingPathComponent("notes.corrupt-\(stamp).json")
        try fileManager.moveItem(at: fileURL, to: aside)
        movedAsideURL = aside
        // Keep the last good backup where future backups can't overwrite it.
        if fileManager.fileExists(atPath: backupURL.path) {
            try? fileManager.copyItem(
                at: backupURL,
                to: folder.appendingPathComponent("notes.corrupt-\(stamp).bak")
            )
        }
    }
}
