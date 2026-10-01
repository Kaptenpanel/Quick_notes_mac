import Foundation

public struct Note: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var body: String
    public let created: Date
    public var modified: Date
    /// Pinned notes list above the rest.
    public var pinned: Bool

    public init(
        id: UUID = UUID(), body: String = "", created: Date = Date(), modified: Date? = nil, pinned: Bool = false
    ) {
        self.id = id
        self.body = body
        self.created = created
        self.modified = modified ?? created
        self.pinned = pinned
    }

    private enum CodingKeys: String, CodingKey {
        case id, body, created, modified, pinned
    }

    // Notes saved before pinning existed have no `pinned` key; they must still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        body = try container.decode(String.self, forKey: .body)
        created = try container.decode(Date.self, forKey: .created)
        modified = try container.decode(Date.self, forKey: .modified)
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
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
}
