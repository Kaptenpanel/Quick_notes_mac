import Foundation

public struct Note: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var body: String
    public let created: Date
    public var modified: Date

    public init(id: UUID = UUID(), body: String = "", created: Date = Date(), modified: Date? = nil) {
        self.id = id
        self.body = body
        self.created = created
        self.modified = modified ?? created
    }

    public static let placeholderTitle = "New Note"

    /// True when the note has no visible text.
    public var isBlank: Bool {
        body.allSatisfy(\.isWhitespace)
    }

    /// First non-empty line, trimmed; nil when the note is blank.
    public var title: String? {
        var result: String?
        body.enumerateLines { line, stop in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                result = trimmed
                stop = true
            }
        }
        return result
    }

    /// Title for display in the list; placeholder when blank.
    public var displayTitle: String {
        title ?? Self.placeholderTitle
    }

    /// Search: true when the body contains the query, ignoring case and accents.
    /// A blank query matches every note.
    public func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return body.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
