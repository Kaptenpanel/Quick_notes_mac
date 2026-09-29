import Foundation

/// A fresh notes-file URL inside a unique temp directory (directory not created).
func makeTempNotesURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("QuickNotesTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("notes.json")
}
