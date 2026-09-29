import Foundation

/// Reads and writes all notes as one JSON file.
///
/// Safety rules:
/// - Missing file loads as an empty list.
/// - Undecodable file is moved aside (never overwritten) and loads as empty.
/// - Any other read error leaves the file alone and makes the store read-only
///   for its lifetime, so a bad load can never be saved over real notes.
/// - The first save of each store instance copies the existing file to `.bak`.
public final class NoteStore {
    public enum LoadError: Error {
        case unreadable(underlying: Error)
    }

    public let fileURL: URL
    public private(set) var isReadOnly = false
    private var didBackUp = false
    private let fileManager = FileManager.default

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("QuickNotes", isDirectory: true)
            .appendingPathComponent("notes.json")
    }

    public var backupURL: URL {
        fileURL.appendingPathExtension("bak")
    }

    public func load() throws -> [Note] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            isReadOnly = true
            throw LoadError.unreadable(underlying: error)
        }

        do {
            return try JSONDecoder().decode([Note].self, from: data)
        } catch {
            try moveCorruptFileAside()
            return []
        }
    }

    public func save(_ notes: [Note]) throws {
        guard !isReadOnly else { return }

        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if !didBackUp {
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: backupURL)
                try fileManager.copyItem(at: fileURL, to: backupURL)
            }
            didBackUp = true
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(notes).write(to: fileURL, options: .atomic)
    }

    private func moveCorruptFileAside() throws {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let aside = fileURL.deletingLastPathComponent()
            .appendingPathComponent("notes.corrupt-\(stamp).json")
        try fileManager.moveItem(at: fileURL, to: aside)
    }
}
