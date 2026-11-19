import Foundation
import ToriCore
import ToriStore

/// One translation variant offered on Add / Entry ("Suggested meanings") or used by the automatic fill.
public struct Suggestion: Hashable, Sendable {
    public var sense: NewSense
    public var isMachine: Bool { sense.source == .mtApple }

    public init(_ sense: NewSense) { self.sense = sense }
}

public enum Suggestions {
    /// Dictionary variants (headword order, sense ordinal, variant rank), deduplicated by translation key, then the MT
    /// variant only if its key differs from all dictionary variants.
    public static func build(headwords: [DictionaryHeadword], dictVersion: String?, machine: String?) -> [Suggestion] {
        var seen = Set<String>()
        var out: [Suggestion] = []
        for hw in headwords {
            for sense in hw.senses.sorted(by: { ($0.ordinal ?? .max) < ($1.ordinal ?? .max) }) {
                for ru in sense.translationsRu {
                    let text = ru.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, seen.insert(TextKey.translationKey(text)).inserted else { continue }
                    out.append(Suggestion(NewSense(
                        translation: text, definition: sense.glossEn, partOfSpeech: hw.partOfSpeech, source: .wiktionary,
                        dictVersion: dictVersion, dictHeadwordKey: hw.key, dictSenseOrdinal: sense.ordinal)))
                }
            }
        }
        if let mt = machine?.trimmingCharacters(in: .whitespacesAndNewlines), !mt.isEmpty,
           !seen.contains(TextKey.translationKey(mt)) {
            out.append(Suggestion(NewSense(translation: mt, source: .mtApple)))
        }
        return out
    }
}
