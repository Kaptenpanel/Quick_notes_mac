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

    /// True when the note has no visible text.
    public var isBlank: Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// First non-empty line, trimmed; nil when the note is blank.
    public var title: String? {
        body.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}
