import Foundation

/// Text keys. Character sets are the explicit lists in `spec/fixtures/README.md`,
/// never a Unicode property lookup or a locale-dependent call, so all platforms agree.
public enum TextKey {
    /// Key for duplicate detection of Entry texts and dictionary lookups.
    public static func matchKey(_ text: String) -> String {
        var s = collapse(Array(lowercase(foldSteps1to3(text)).unicodeScalars))[...]
        while let f = s.first, isPunctuation(f) || isWhitespace(f) { s.removeFirst() }
        while let l = s.last, isPunctuation(l) || isWhitespace(l) { s.removeLast() }
        return yo(string(s))
    }

    /// Key for duplicate translations within an Entry (same rules as `matchKey`).
    public static func translationKey(_ text: String) -> String { matchKey(text) }

    /// Key for duplicate Context sentences: case is kept.
    public static func sentenceKey(_ text: String) -> String { yo(collapse(foldSteps1to3(text))) }

    /// Key for Tag names: NFC, lowercase, collapse, ё → е (no quote mapping, no ignorable removal).
    public static func tagKey(_ text: String) -> String { yo(collapse(lowercase(nfc(text)))) }

    /// Search fold for the Words list search (no edge stripping).
    public static func searchFold(_ text: String) -> String { yo(collapse(lowercase(foldSteps1to3(text)))) }

    /// An Entry text is a phrase when its match key contains whitespace.
    public static func isPhrase(_ text: String) -> Bool { matchKey(text).unicodeScalars.contains(" ") }

    // MARK: - Explicit character lists

    static let singleQuotes: Set<Unicode.Scalar> = ["\u{2019}", "\u{2018}", "\u{02BC}", "\u{2032}"]
    static let doubleQuotes: Set<Unicode.Scalar> = ["\u{201C}", "\u{201D}", "\u{201E}", "\u{2033}"]
    static let dashes: Set<Unicode.Scalar> = ["\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}"]
    /// Space separators (Zs) other than U+0020.
    static let spaceSeparators: Set<Unicode.Scalar> = Set(
        [0x00A0, 0x1680, 0x202F, 0x205F, 0x3000].compactMap(Unicode.Scalar.init)
            + (0x2000...0x200A).compactMap(Unicode.Scalar.init))
    /// Removed outright: soft hyphen, ZWSP, ZWNJ, ZWJ, word joiner, BOM.
    static let defaultIgnorables: Set<Unicode.Scalar> = ["\u{00AD}", "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}"]
    /// Whitespace for collapse, trim and tokens.
    static let whitespace: Set<Unicode.Scalar> = ["\t", "\n", "\u{0B}", "\u{0C}", "\r", " ", "\u{85}", "\u{2028}", "\u{2029}"]

    static func isWhitespace(_ c: Unicode.Scalar) -> Bool { whitespace.contains(c) }

    static func isPunctuation(_ c: Unicode.Scalar) -> Bool {
        switch c.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation: true
        default: false
        }
    }

    // MARK: - Steps

    static func nfc(_ s: String) -> String { s.precomposedStringWithCanonicalMapping }

    /// NFC, quote/dash/space mapping, default-ignorable removal.
    static func foldSteps1to3(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for c in nfc(s).unicodeScalars where !defaultIgnorables.contains(c) {
            if singleQuotes.contains(c) { out.append("'") }
            else if doubleQuotes.contains(c) { out.append("\"") }
            else if dashes.contains(c) { out.append("-") }
            else if spaceSeparators.contains(c) { out.append(" ") }
            else { out.append(c) }
        }
        return String(out)
    }

    /// Full default lowercase mapping per code point: no locale, no context (Σ → σ, never ς).
    static func lowercase(_ s: String) -> String {
        var out = ""
        for c in s.unicodeScalars { out += c.properties.lowercaseMapping }
        return out
    }

    /// Runs of whitespace → one U+0020; leading and trailing whitespace removed.
    static func collapse(_ s: String) -> String { string(collapse(Array(s.unicodeScalars))) }

    static func string(_ scalars: some Sequence<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    static func collapse(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        var pending = false
        for c in s {
            if isWhitespace(c) {
                pending = true
            } else {
                if pending && !out.isEmpty { out.append(" ") }
                pending = false
                out.append(c)
            }
        }
        return out
    }

    static func yo(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for c in s.unicodeScalars {
            out.append(c == "ё" ? "е" : c == "Ё" ? "Е" : c)
        }
        return String(out)
    }
}

/// Natural key of a Source without URL.
public struct SourceKey: Hashable, Sendable {
    public var title: String
    public var app: String?
    public var suggested: Bool

    public init(title: String?, app: String?, isSuggested: Bool) {
        self.title = TextKey.matchKey(title ?? "")
        self.app = app
        self.suggested = isSuggested
    }
}
