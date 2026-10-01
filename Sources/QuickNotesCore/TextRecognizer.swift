import CoreGraphics
import Foundation
import Vision

/// Pulls text out of images (screenshots, photos of code) on-device with Vision.
public enum TextRecognizer {
    public enum Failure: Error {
        case noText
    }

    /// One recognized line of text. `box` is normalized (0…1) with the origin at the bottom left.
    public struct Line: Sendable, Equatable {
        public var text: String
        public var box: CGRect

        public init(text: String, box: CGRect) {
            self.text = text
            self.box = box
        }
    }

    public static func recognizeText(in imageData: Data) async throws -> String {
        let aspect = CGImageSourceCreateWithData(imageData as CFData, nil).flatMap(aspectRatio) ?? 1
        return try await recognize(aspect: aspect) { VNImageRequestHandler(data: imageData) }
    }

    public static func recognizeText(at url: URL) async throws -> String {
        let aspect = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(aspectRatio) ?? 1
        return try await recognize(aspect: aspect) { VNImageRequestHandler(url: url) }
    }

    public static func recognizeText(in image: CGImage) async throws -> String {
        try await recognize(aspect: CGFloat(image.width) / CGFloat(image.height)) {
            VNImageRequestHandler(cgImage: image)
        }
    }

    /// Vision reads an icon as whatever character it resembles ("®", "@", "*"). Those stand alone
    /// and are at least about as wide as the line is tall; real symbols in text are narrower.
    /// `width` gives a character's width as a fraction of its line's height.
    public static func labelIcons(_ text: String, width: (Range<String.Index>) -> CGFloat?) -> String {
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            let character = text[index]
            let standsAlone = (index == text.startIndex || text[text.index(before: index)] == " ")
                && (next == text.endIndex || text[next] == " ")
            // Latin letters can be whole words ("a", "I", Swedish "å"); digits are list numbers.
            let isWordCharacter = character.isNumber
                || (character.isLetter && character.unicodeScalars.allSatisfy { $0.value < 0x250 })
            if standsAlone, !isWordCharacter, let w = width(index..<next), w >= 0.9 {
                output += "[icon]"
            } else {
                output.append(character)
            }
            index = next
        }
        return output
    }

    /// Rebuilds the image's line layout: fragments at the same height join into one line,
    /// and a noticeably larger vertical gap becomes a blank line.
    public static func layout(_ lines: [Line]) -> String {
        let fragments = lines
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.box.midY > $1.box.midY }
        guard !fragments.isEmpty else { return "" }

        var rows: [[Line]] = []
        for fragment in fragments {
            if let last = rows.last?.last,
               abs(last.box.midY - fragment.box.midY) < min(last.box.height, fragment.box.height) / 2 {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }

        let heights = fragments.map(\.box.height).sorted()
        let typicalHeight = heights[heights.count / 2]

        var output: [String] = []
        var previousBottom: CGFloat?
        for row in rows {
            let top = row.map(\.box.maxY).max()!
            if let previousBottom, previousBottom - top > typicalHeight {
                output.append("")
            }
            let text = row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
            // Vision often reads angle brackets as single guillemets, which breaks pasted commands.
            output.append(text.replacingOccurrences(of: "‹", with: "<").replacingOccurrences(of: "›", with: ">"))
            previousBottom = row.map(\.box.minY).min()!
        }
        return output.joined(separator: "\n")
    }

    /// Vision sometimes reads the ring on "å" as a breve or hook, giving Romanian "ă" ("pă" for "på")
    /// or Vietnamese "ả".
    /// Swap such lookalikes back when only the intended letter is in the user's languages.
    public static func fixLookalikes(_ text: String, languages: [String]) -> String {
        let alphabet = languages.reduce(into: CharacterSet()) { result, identifier in
            if let letters = (Locale(identifier: identifier) as NSLocale).object(forKey: .exemplarCharacterSet) as? CharacterSet {
                result.formUnion(letters)
            }
        }
        var text = text
        for (misread, intended) in [("ă", "å"), ("Ă", "Å"), ("ả", "å"), ("Ả", "Å")]
        where alphabet.contains(intended.lowercased().unicodeScalars.first!)
            && !alphabet.contains(misread.lowercased().unicodeScalars.first!) {
            text = text.replacingOccurrences(of: misread, with: intended)
        }
        return text
    }

    // MARK: Private

    /// Width over height in pixels; Vision's normalized boxes need it to compare widths with heights.
    private static func aspectRatio(_ source: CGImageSource) -> CGFloat? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat, height > 0
        else { return nil }
        return width / height
    }

    private static func recognize(
        aspect: CGFloat,
        _ makeHandler: @escaping @Sendable () -> VNImageRequestHandler
    ) async throws -> String {
        // Vision blocks while it works, so keep it off the caller's thread.
        try await Task.detached(priority: .userInitiated) {
            let handler = makeHandler()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            // Language correction "fixes" code and command lines (flags, paths, identifiers).
            request.usesLanguageCorrection = false
            try handler.perform([request])

            let lines = (request.results ?? []).compactMap { observation -> Line? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let lineHeight = observation.boundingBox.height
                let text = labelIcons(candidate.string) { range in
                    guard lineHeight > 0, let box = try? candidate.boundingBox(for: range)?.boundingBox else { return nil }
                    return box.width * aspect / lineHeight
                }
                return Line(text: text, box: observation.boundingBox)
            }
            let text = fixLookalikes(layout(lines), languages: Locale.preferredLanguages)
            guard !text.isEmpty else { throw Failure.noText }
            return text
        }.value
    }
}
