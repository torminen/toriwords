import Foundation
import ToriCore
import ToriStore

/// One autocomplete row on Add (§6.2 items 1–2): a saved Entry ("In your vocabulary") or a dictionary headword.
public struct Completion: Hashable, Sendable {
    public var text: String
    public var partOfSpeech: String?
    public var translation: String?
    /// English gloss (related-word preview).
    public var definition: String?
    /// Set when the word is already saved; tapping the row opens that Entry.
    public var entry: ToriID?

    public init(text: String, partOfSpeech: String? = nil, translation: String? = nil, definition: String? = nil,
                entry: ToriID? = nil) {
        self.text = text
        self.partOfSpeech = partOfSpeech
        self.translation = translation
        self.definition = definition
        self.entry = entry
    }
}

public enum Autocomplete {
    public static let minCharacters = 2
    public static let vocabularyLimit = 3
    public static let totalLimit = 8

    public enum Input: Equatable, Sendable {
        case tooShort
        case english(String)
        /// Cyrillic and no Latin letters: reverse lookup (P1, §6.2 item 2).
        case russian(String)
    }

    public static func classify(_ text: String) -> Input {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minCharacters else { return .tooShort }
        let scalars = trimmed.unicodeScalars
        let latin = scalars.contains { ("a"..."z").contains($0) || ("A"..."Z").contains($0) }
        let cyrillic = scalars.contains { (0x0400...0x04FF).contains($0.value) }
        return cyrillic && !latin ? .russian(trimmed) : .english(trimmed)
    }

    /// Saved Entries first (up to 3), then dictionary rows whose key is not already listed, up to 8 in total.
    public static func merge(vocabulary: [Completion], dictionary: [Completion]) -> [Completion] {
        let saved = Array(vocabulary.prefix(vocabularyLimit))
        var seen = Set(saved.map { TextKey.matchKey($0.text) })
        var out = saved
        for row in dictionary where out.count < totalLimit {
            if seen.insert(TextKey.matchKey(row.text)).inserted { out.append(row) }
        }
        return out
    }
}

/// The Add preview form (§5.1, doc 35 §3.2): variants to check, own translation, sentence, source, tags.
public struct AddDraft: Equatable, Sendable {
    public struct Variant: Hashable, Sendable {
        public var sense: NewSense
        public var isChecked: Bool
        /// A meaning the saved Entry already has: shown checked and disabled (8-6 A2).
        public var isExisting: Bool
        public var isMachine: Bool { sense.source == .mtApple || sense.source == .mtMLKit }
    }

    public var text: String
    public var variants: [Variant] = []
    public var ownTranslation = ""
    public var sentence = ""
    public var source = ""
    public var tags: [String] = []
    /// The saved Entry with the same match key, if any.
    public var existingEntry: ToriID?

    public init(text: String) { self.text = text }

    /// Existing meanings come first (checked, disabled); new suggestions follow. The first new one is preselected only
    /// for a new word, so Save on a saved word never adds a meaning the user did not pick.
    public mutating func setSuggestions(_ suggestions: [Suggestion], existing: [String] = [], existingEntry: ToriID? = nil) {
        self.existingEntry = existingEntry
        var seen = Set<String>()
        variants = existing.compactMap { t in
            guard seen.insert(TextKey.translationKey(t)).inserted else { return nil }
            return Variant(sense: NewSense(translation: t), isChecked: true, isExisting: true)
        }
        for s in suggestions {
            guard let t = s.sense.translation, seen.insert(TextKey.translationKey(t)).inserted else { continue }
            variants.append(Variant(sense: s.sense, isChecked: false, isExisting: false))
        }
        if existingEntry == nil, let first = variants.firstIndex(where: { !$0.isExisting }) { variants[first].isChecked = true }
    }

    public mutating func toggle(_ index: Int) {
        guard variants.indices.contains(index), !variants[index].isExisting else { return }
        variants[index].isChecked.toggle()
    }

    private var cleaned: Capture.Cleaned { Capture.clean(text) }

    /// Save needs a Latin letter; text of only spaces or punctuation is rejected (§5.1, §5.2).
    public var canSave: Bool { cleaned.isSaveable }

    /// More than 6 words or sentence punctuation: offer to keep it as the sentence and pick the word (§5.1).
    public var looksLikeSentence: Bool { cleaned.isSaveable && cleaned.kind == .sentence }

    /// "Tap the word to save": takes chips `first...last` of the typed sentence as the word, the sentence as context.
    public mutating func pick(firstChip: Int, lastChip: Int) {
        let x = Capture.extract(cleaned, firstChip: firstChip, lastChip: lastChip)
        text = x.entryText
        sentence = x.sentence
    }

    /// The capture for Save: checked new variants, then the own translation; empty optional fields are left out.
    public func captureInput(now: Int64) -> CaptureInput {
        let term = cleaned.text
        var senses = variants.filter { $0.isChecked && !$0.isExisting }.map(\.sense)
        let own = ownTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { senses.append(NewSense(translation: own)) }
        let sentence = Capture.clean(self.sentence).text
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return CaptureInput(
            term: term, capturedAt: now, origin: "typed", senses: senses,
            sentence: sentence.isEmpty ? nil : sentence,
            highlight: sentence.isEmpty ? nil : Capture.typedHighlight(sentence: sentence, entryText: term),
            source: source.isEmpty ? nil : SourceInput(kind: .other, title: source),
            tags: tags.filter { !TextKey.tagKey($0).isEmpty })
    }
}
