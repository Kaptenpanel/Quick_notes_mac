import Foundation

/// Reads and writes all notes as one JSON file.
///
/// Safety rules:
/// - Missing file loads as an empty list.
/// - Undecodable file is moved aside (never overwritten) and loads as empty.
/// - Any other load failure leaves the file alone and makes the store read-only
///   for its lifetime, so a bad load can never be saved over real notes.
/// - The first save of each store instance copies the existing file to `.bak`.
public final class NoteStore {
    public struct ReadOnlyError: Error {}

    public let fileURL: URL
    public private(set) var isReadOnly = false
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
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: backupURL)
                try fileManager.copyItem(at: fileURL, to: backupURL)
            }
            didPrepareFirstSave = true
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(notes).write(to: fileURL, options: .atomic)
    }

    private func moveCorruptFileAside() throws {
        let stamp = Date.now.formatted(.iso8601.timeSeparator(.omitted))
        let aside = fileURL.deletingLastPathComponent()
            .appendingPathComponent("notes.corrupt-\(stamp).json")
        try fileManager.moveItem(at: fileURL, to: aside)
    }
}
