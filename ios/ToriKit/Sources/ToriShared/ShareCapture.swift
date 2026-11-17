import Foundation
import ToriCore

/// What the Share Extension received (doc 36 §5.1): text/URL items, plus the Safari JavaScript preprocessing result
/// (`ExtensionPreprocessing.js`: `selection`, `title`, `url`, `sentence`) when the share came from Safari.
public struct SharePayload: Hashable, Sendable {
    public var text: String?
    public var url: String?
    public var title: String?
    /// The sentence around the selection (Safari only).
    public var sentence: String?
    /// The preprocessing result was present: only Safari runs it (§4 `source.app`, CH-23).
    public var fromSafari: Bool

    public init(text: String? = nil, url: String? = nil, title: String? = nil, sentence: String? = nil, fromSafari: Bool = false) {
        self.text = text
        self.url = url
        self.title = title
        self.sentence = sentence
        self.fromSafari = fromSafari
    }

    /// `javaScript` is the preprocessing dictionary (string values; other values ignored); `texts`/`urls` the item
    /// providers' plain-text and URL items in order. A text item that is only an http(s) URL counts as the URL.
    public init(javaScript: [String: String]?, texts: [String], urls: [String]) {
        func value(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }
        var url = value(javaScript?["url"]) ?? urls.lazy.compactMap(value).first
        var text = value(javaScript?["selection"])
        if text == nil {
            for t in texts.compactMap(value) {
                if Self.isWebURL(t) { url = url ?? t } else { text = t; break }
            }
        }
        if text == url { text = nil }
        self.init(text: text, url: url, title: value(javaScript?["title"]), sentence: value(javaScript?["sentence"]),
                  fromSafari: javaScript != nil)
    }

    static func isWebURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        return (lower.hasPrefix("http://") || lower.hasPrefix("https://")) && !s.contains(where: \.isWhitespace)
    }

    /// The URL's host without a leading `www.`.
    public var domain: String? {
        guard let host = url.flatMap({ URL(string: $0)?.host }), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// "Safari · theguardian.com" when detectably from Safari, else the domain alone (Product C16).
    public var sourceLabel: String? {
        guard let domain else { return fromSafari ? "Safari" : nil }
        return fromSafari ? "Safari · \(domain)" : domain
    }
}

/// The capture sheet's text state (doc 36 §5.2): cleaned text, word chips and the picked span, the sentence and
/// its highlight, and the inbox file it saves.
public struct CaptureDraft: Equatable, Sendable {
    public private(set) var cleaned: Capture.Cleaned
    /// Word chips (sentence sources only), as display strings.
    public private(set) var chips: [String] = []
    private var chipRanges: [Capture.Chip] = []
    /// Picked chip indices (sentence sources).
    public private(set) var selection: ClosedRange<Int>?
    /// Context sentence and highlight. Sentence sources: from the picked span; term sources: the Safari sentence
    /// around the selection, or a sentence the user typed.
    public private(set) var sentence: String?
    public private(set) var highlight: Capture.Highlight?
    private var sentenceTyped = false

    public init(_ payload: SharePayload) {
        cleaned = Capture.clean(payload.text ?? "")
        reset()
        if cleaned.kind == .term, let s = payload.sentence { attachSentence(s) }
    }

    public var isSentenceSource: Bool { cleaned.kind == .sentence }

    /// The Entry text; nil until a chip is picked in a sentence source or when the text is empty.
    public var term: String? {
        if isSentenceSource {
            guard let r = selection else { return nil }
            return Capture.extract(cleaned, firstChip: r.lowerBound, lastChip: r.upperBound).entryText
        }
        return cleaned.text.isEmpty ? nil : cleaned.text
    }

    /// False with no Latin letter ("ToriWords saves English words and phrases") or nothing picked.
    public var canSave: Bool { cleaned.isSaveable && term != nil }

    /// The user edited the text (non-Latin selection, link-only share): clean and classify again.
    public mutating func editText(_ text: String) {
        cleaned = Capture.clean(text)
        reset()
        if let s = sentence, sentenceTyped { highlight = Capture.typedHighlight(sentence: s, entryText: cleaned.text) }
        else if isSentenceSource { sentence = nil; highlight = nil }
    }

    /// Tap on chip `i`: picks it; a chip next to the picked span extends it (phrase); a picked end chip shrinks it;
    /// the single picked chip unpicks; any other chip starts a new pick.
    public mutating func tapChip(_ i: Int) {
        guard chips.indices.contains(i) else { return }
        if let r = selection {
            if r == i...i { selection = nil }
            else if i == r.lowerBound - 1 { selection = i...r.upperBound }
            else if i == r.upperBound + 1 { selection = r.lowerBound...i }
            else if i == r.lowerBound { selection = (i + 1)...r.upperBound }
            else if i == r.upperBound { selection = r.lowerBound...(i - 1) }
            else { selection = i...i }
        } else {
            selection = i...i
        }
        if let r = selection {
            let e = Capture.extract(cleaned, firstChip: r.lowerBound, lastChip: r.upperBound)
            (sentence, highlight) = (e.sentence, e.highlight)
        } else {
            (sentence, highlight) = (nil, nil)
        }
    }

    /// A sentence typed or edited in the sheet (term sources): highlight = first occurrence of the term (§5.2 step 6).
    public mutating func editSentence(_ text: String) {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        sentenceTyped = true
        sentence = s.isEmpty ? nil : s
        highlight = sentence.flatMap { s in term.flatMap { Capture.typedHighlight(sentence: s, entryText: $0) } }
    }

    private mutating func reset() {
        selection = nil
        chipRanges = isSentenceSource ? Capture.chips(cleaned.text) : []
        let scalars = Array(cleaned.text.unicodeScalars)
        chips = chipRanges.map { scalarString(scalars[$0.start..<$0.end]) }
    }

    /// Safari's sentence around a term: the chip span equal to the term (match key) gives the cut and highlight;
    /// otherwise the first occurrence; dropped when the term is not in it and it is too long to keep whole.
    private mutating func attachSentence(_ raw: String) {
        guard let term else { return }
        let c = Capture.clean(raw)
        let key = TextKey.matchKey(term)
        let scalars = Array(c.text.unicodeScalars)
        let cs = Capture.chips(c.text)
        let width = TextKey.matchKey(term).split(separator: " ").count
        for i in cs.indices {
            let j = i + width - 1
            guard j < cs.count else { break }
            if TextKey.matchKey(scalarString(scalars[cs[i].start..<cs[j].end])) == key {
                let e = Capture.extract(c, firstChip: i, lastChip: j)
                (sentence, highlight) = (e.sentence, e.highlight)
                return
            }
        }
        guard scalars.count <= Capture.maxSentence, !c.text.isEmpty else { return }
        (sentence, highlight) = (c.text, Capture.typedHighlight(sentence: c.text, entryText: term))
    }

    /// The inbox file for Save (§5.3.1); nil when the draft cannot be saved. Blank title/typed translation are dropped.
    public func inboxFile(captureId: ToriID, capturedAt: Int64, utcOffsetMin: Int, payload: SharePayload,
                          sourceTitle: String?, tags: [String], chosenSenses: [InboxFile.ChosenSense],
                          typedTranslation: String?, resume: Bool) -> InboxFile? {
        guard canSave, let term else { return nil }
        let title = sourceTitle.flatMap(Self.nonBlank)
        let source = (payload.url != nil || title != nil)
            ? InboxFile.Source(url: payload.url, title: title, app: payload.fromSafari ? "Safari" : nil) : nil
        return InboxFile(captureId: captureId, capturedAt: capturedAt, utcOffsetMin: utcOffsetMin, term: term,
                         sentence: sentence, highlight: sentence == nil ? nil : highlight, source: source,
                         tags: tags.isEmpty ? nil : tags, chosenSenses: chosenSenses,
                         typedTranslation: typedTranslation.flatMap(Self.nonBlank), origin: "shared", resume: resume)
    }

    static func nonBlank(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// Tag names typed in the sheet: comma-separated, trimmed, first spelling kept per tag key.
public enum TagInput {
    public static func names(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",").compactMap { part in
            let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(TextKey.tagKey(name)).inserted else { return nil }
            return name
        }
    }

    /// Suggestions: sticky tags first, then the index's tag names, without repeats by key.
    public static func suggestions(sticky: [String], index: [VocabIndex.Tag]) -> [String] {
        names((sticky + index.map(\.name)).joined(separator: ","))
    }
}

extension CaptureSticky {
    /// After Save (§5.5): this capture's title and tags are offered for 30 minutes; the tip flag is kept.
    public static func afterSave(now: Int64, sourceTitle: String?, tags: [String], previous: CaptureSticky?) -> CaptureSticky {
        CaptureSticky(updatedAt: now, sourceTitle: sourceTitle.flatMap(CaptureDraft.nonBlank), tags: tags,
                      tipShown: previous?.tipShown ?? false)
    }

    /// The one-time tip was shown: set the flag, keep the offered values and their window.
    public static func tipShown(previous: CaptureSticky?) -> CaptureSticky {
        var s = previous ?? CaptureSticky(updatedAt: 0, sourceTitle: nil, tags: [], tipShown: true)
        s.tipShown = true
        return s
    }
}

private func scalarString(_ s: ArraySlice<Unicode.Scalar>) -> String { String(String.UnicodeScalarView(s)) }
