// ToriUI: shared SwiftUI components and design tokens (doc 36 §2.3, doc 35 §4).
// SwiftUI files are wrapped in `#if canImport(SwiftUI)` so ToriKit builds on Linux; this file is plain Swift.
import ToriCore

/// A sentence split around its highlighted Entry text (`highlight` is in UTF-16 code units, doc 36 §4.2).
public struct SentenceMarkup: Hashable, Sendable {
    public var before: String
    public var word: String
    public var after: String

    /// Recall fronts replace the whole word or phrase with this (doc 35 §3.4).
    public static let blank = "______"

    /// nil when there is no highlight or it does not fall on character boundaries inside the sentence.
    public init?(sentence: String, highlight: Capture.Highlight?) {
        guard let h = highlight, h.offset >= 0, h.length > 0 else { return nil }
        let utf16 = sentence.utf16
        guard h.offset + h.length <= utf16.count,
              let lo = utf16.index(utf16.startIndex, offsetBy: h.offset).samePosition(in: sentence),
              let hi = utf16.index(utf16.startIndex, offsetBy: h.offset + h.length).samePosition(in: sentence)
        else { return nil }
        before = String(sentence[..<lo])
        word = String(sentence[lo..<hi])
        after = String(sentence[hi...])
    }

    public var blanked: String { before + Self.blank + after }
}
