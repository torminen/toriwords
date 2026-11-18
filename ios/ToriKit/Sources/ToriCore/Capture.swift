/// Capture text rules, doc 36 §5.2. Lengths and cuts count Unicode code points; highlight offsets
/// and lengths are UTF-16 code units of the stored sentence (what `NSRange` and Kotlin use).
public enum Capture {
    public static let maxCharacters = 5000
    public static let maxSentence = 500
    public static let sentenceWordThreshold = 6

    public enum Kind: String, Sendable { case term, sentence }

    /// Result of steps 1–3 on shared or pasted text.
    public struct Cleaned: Equatable, Sendable {
        public var text: String
        public var kind: Kind
        /// False when the text has no Latin letter: the capture is rejected.
        public var isSaveable: Bool
        /// Code-point offsets in `text` where a line break started a new line (sentence boundaries).
        var lineStarts: [Int]
    }

    /// A highlighted range in UTF-16 code units.
    public struct Highlight: Hashable, Codable, Sendable {
        public var offset: Int
        public var length: Int
        public init(offset: Int, length: Int) {
            self.offset = offset
            self.length = length
        }
    }

    /// A word chip: code-point range in the cleaned text.
    public struct Chip: Hashable, Sendable {
        public var start: Int
        public var end: Int
    }

    public struct Extraction: Equatable, Sendable {
        public var entryText: String
        public var sentence: String
        public var highlight: Highlight
    }

    static let terminals: Set<Unicode.Scalar> = [".", "!", "?", "…"]
    static let closers: Set<Unicode.Scalar> = ["\"", "'", "\u{201D}", "\u{2019}", "\u{00BB}", ")", "]"]
    static let ellipsis: Unicode.Scalar = "…"
    /// "Space" for speaker labels: whitespace plus the Zs space separators.
    static let speakerSpace = TextKey.whitespace.union(TextKey.spaceSeparators)

    // MARK: Steps 1–3

    public static func clean(_ text: String) -> Cleaned {
        let s = stripAnnotations(stripTags(Array(text.unicodeScalars)))
        var out: [Unicode.Scalar] = []
        var starts: [Int] = []
        for line in lines(s) {
            let cleaned = TextKey.collapse(Array(stripSpeaker(line)))
            if cleaned.isEmpty { continue }
            if !out.isEmpty {
                starts.append(out.count + 1)
                out.append(" ")
            }
            out += cleaned
        }
        out = TextKey.collapse(Array(out.prefix(maxCharacters)))
        let words = out.isEmpty ? 0 : out.split(separator: " ", omittingEmptySubsequences: false).count
        let kind: Kind = words > sentenceWordThreshold || endsSentence(out, at: out.count) ? .sentence : .term
        return Cleaned(text: TextKey.string(out), kind: kind, isSaveable: out.contains(where: isLatinLetter),
                       lineStarts: starts.filter { $0 < out.count })
    }

    static func stripTags(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        var i = 0
        while i < s.count {
            if s[i] == "<", let j = s[(i + 1)...].firstIndex(where: { $0 == "<" || $0 == ">" }), s[j] == ">" {
                i = j + 1
                continue
            }
            out.append(s[i])
            i += 1
        }
        return out
    }

    /// Removes `[..]` and `(..)` whose content is one or more letters (L*) or U+0020; removed spans are not rescanned.
    static func stripAnnotations(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        var i = 0
        while i < s.count {
            let close: Unicode.Scalar? = s[i] == "[" ? "]" : s[i] == "(" ? ")" : nil
            if let close {
                var j = i + 1
                while j < s.count && (s[j] == " " || isLetter(s[j])) { j += 1 }
                if j > i + 1 && j < s.count && s[j] == close {
                    i = j + 1
                    continue
                }
            }
            out.append(s[i])
            i += 1
        }
        return out
    }

    /// Lines split at CRLF, CR or LF.
    static func lines(_ s: [Unicode.Scalar]) -> [ArraySlice<Unicode.Scalar>] {
        var result: [ArraySlice<Unicode.Scalar>] = []
        var start = 0, i = 0
        while i < s.count {
            if s[i] == "\r" || s[i] == "\n" {
                result.append(s[start..<i])
                i += (s[i] == "\r" && i + 1 < s.count && s[i + 1] == "\n") ? 2 : 1
                start = i
            } else {
                i += 1
            }
        }
        result.append(s[start..<s.count])
        return result
    }

    /// Leading speaker label: up to 3 words (runs without space or ':') separated by spaces/tabs, then ':'
    /// followed by a space or the line end; trailing spaces/tabs go too.
    static func stripSpeaker(_ line: ArraySlice<Unicode.Scalar>) -> ArraySlice<Unicode.Scalar> {
        func isBlank(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\t" }
        var i = line.startIndex
        while i < line.endIndex && isBlank(line[i]) { i += 1 }
        for word in 1...3 {
            let start = i
            while i < line.endIndex && line[i] != ":" && !speakerSpace.contains(line[i]) { i += 1 }
            if i == start || i == line.endIndex { return line }
            if line[i] == ":" {
                guard i + 1 == line.endIndex || speakerSpace.contains(line[i + 1]) else { return line }
                i += 1
                while i < line.endIndex && isBlank(line[i]) { i += 1 }
                return line[i...]
            }
            guard isBlank(line[i]), word < 3 else { return line }
            while i < line.endIndex && isBlank(line[i]) { i += 1 }
        }
        return line
    }

    /// True if `s[..<end]` ends with a terminal followed by optional closers.
    static func endsSentence(_ s: [Unicode.Scalar], at end: Int) -> Bool {
        var i = end
        while i > 0 && closers.contains(s[i - 1]) { i -= 1 }
        return i > 0 && terminals.contains(s[i - 1])
    }

    public static func isLatinLetter(_ c: Unicode.Scalar) -> Bool {
        switch c.value {
        case 0x41...0x5A, 0x61...0x7A, 0x1E00...0x1EFF: true
        case 0xD7, 0xF7: false
        case 0xC0...0x24F: true
        default: false
        }
    }

    static func isLetter(_ c: Unicode.Scalar) -> Bool {
        switch c.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: true
        default: false
        }
    }

    static func isLetterOrNumber(_ c: Unicode.Scalar) -> Bool {
        if isLetter(c) { return true }
        switch c.properties.generalCategory {
        case .decimalNumber, .letterNumber, .otherNumber: return true
        default: return false
        }
    }

    // MARK: Steps 4–5

    /// Word chips: whitespace tokens of the cleaned text with edge punctuation (P*) stripped; empty ones dropped.
    public static func chips(_ cleaned: String) -> [Chip] {
        chips(Array(cleaned.unicodeScalars))
    }

    static func chips(_ s: [Unicode.Scalar]) -> [Chip] {
        var out: [Chip] = []
        var pos = 0
        for token in s.split(separator: " ", omittingEmptySubsequences: false) {
            var a = pos, b = pos + token.count
            while a < b && TextKey.isPunctuation(s[a]) { a += 1 }
            while b > a && TextKey.isPunctuation(s[b - 1]) { b -= 1 }
            if a < b { out.append(Chip(start: a, end: b)) }
            pos += token.count + 1
        }
        return out
    }

    /// Entry text, its sentence (cut to ≤ 500 code points) and the highlight, for chips `first...last` of the cleaned text.
    public static func extract(_ cleaned: Cleaned, firstChip: Int, lastChip: Int) -> Extraction {
        let s = Array(cleaned.text.unicodeScalars)
        let cs = chips(s)
        let spanStart = cs[firstChip].start, spanEnd = cs[lastChip].end
        var starts = Set(cleaned.lineStarts)
        for i in s.indices where s[i] == " " && endsSentence(s, at: i) { starts.insert(i + 1) }
        let sentStart = ([0] + starts.filter { $0 <= spanStart }).max()!
        let sentEnd = starts.filter { $0 >= spanEnd }.min() ?? s.count
        var sentence = Array(s[sentStart..<sentEnd])
        while let l = sentence.last, TextKey.isWhitespace(l) { sentence.removeLast() }
        var hl = (spanStart - sentStart, spanEnd - sentStart)
        if sentence.count > maxSentence { (sentence, hl) = cut(sentence, hl) }
        return Extraction(entryText: TextKey.string(s[spanStart..<spanEnd]), sentence: TextKey.string(sentence),
                          highlight: Highlight(offset: utf16Count(sentence[..<hl.0]), length: utf16Count(sentence[hl.0..<hl.1])))
    }

    /// Cuts to ≤ 500 code points around the span at word boundaries, marking cut sides with '…':
    /// grows one word left, then one right, while the result still fits.
    static func cut(_ s: [Unicode.Scalar], _ hl: (Int, Int)) -> ([Unicode.Scalar], (Int, Int)) {
        var words: [(Int, Int)] = []
        var pos = 0
        for token in s.split(separator: " ", omittingEmptySubsequences: false) {
            words.append((pos, pos + token.count))
            pos += token.count + 1
        }
        let first = words.firstIndex { $0.1 > hl.0 }!
        let last = words.lastIndex { $0.0 < hl.1 }!
        func render(_ a: Int, _ b: Int) -> ([Unicode.Scalar], Int) {
            let prefix: [Unicode.Scalar] = a == 0 ? [] : [ellipsis]
            let suffix: [Unicode.Scalar] = b == words.count - 1 ? [] : [ellipsis]
            return (prefix + s[words[a].0..<words[b].1] + suffix, prefix.count - words[a].0)
        }
        var a = first, b = last, grew = true
        while grew {
            grew = false
            if a > 0 && render(a - 1, b).0.count <= maxSentence { a -= 1; grew = true }
            if b < words.count - 1 && render(a, b + 1).0.count <= maxSentence { b += 1; grew = true }
        }
        let (out, shift) = render(a, b)
        return (out, (hl.0 + shift, hl.1 + shift))
    }

    static func utf16Count(_ s: some Sequence<Unicode.Scalar>) -> Int { s.reduce(0) { $0 + UTF16.width($1) } }

    // MARK: Step 6

    /// Highlight for a typed sentence: the first slice at word boundaries (smallest start, then smallest end)
    /// whose match key equals the Entry's; nil if none.
    public static func typedHighlight(sentence: String, entryText: String) -> Highlight? {
        let key = TextKey.matchKey(entryText)
        if key.unicodeScalars.isEmpty { return nil }
        let keyScalars = Array(key.unicodeScalars)
        let s = Array(sentence.unicodeScalars)
        for a in s.indices where isLetterOrNumber(s[a]) && (a == 0 || !isLetterOrNumber(s[a - 1])) {
            for b in (a + 1)...s.count where isLetterOrNumber(s[b - 1]) && (b == s.count || !isLetterOrNumber(s[b])) {
                if Array(TextKey.matchKey(TextKey.string(s[a..<b])).unicodeScalars) == keyScalars {
                    return Highlight(offset: utf16Count(s[..<a]), length: utf16Count(s[a..<b]))
                }
            }
        }
        return nil
    }
}
