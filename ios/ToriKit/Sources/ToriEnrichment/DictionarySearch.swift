import ToriCore
import ToriDictionary
import ToriStore

/// The dictionary searches Add and the Entry screen make (§6.2 items 1–3, 8), as app-shaped `Completion` rows. With no
/// dictionary installed every search answers nothing, which the screens show as "not in the dictionary".
public struct DictionarySearch: Sendable {
    public let dictionary: BundledDictionary?

    public init(_ dictionary: BundledDictionary?) { self.dictionary = dictionary }

    /// Reverse RU → EN starts at 2 Cyrillic letters: a 1-letter FTS prefix scan costs ~30 ms per keystroke.
    public static let reverseMinLetters = 2

    /// Headwords whose key starts with the typed key, phrases included, in dictionary order (§6.2 item 1b).
    public func complete(_ prefix: String, limit: Int) -> [Completion] {
        let key = TextKey.matchKey(prefix)
        return ((try? dictionary?.autocomplete(prefix: key, limit: limit)) ?? []).map(Self.row)
    }

    /// English candidates for Russian input (P1, §6.2 item 2), each with the Russian variant that matched.
    public func reverse(_ russian: String, limit: Int) -> [Completion] {
        guard russian.unicodeScalars.filter({ $0.properties.isAlphabetic }).count >= Self.reverseMinLetters else { return [] }
        return ((try? dictionary?.reverse(russian, limit: limit)) ?? []).map {
            var row = Self.row($0.headword)
            row.translation = $0.matchedTranslation
            return row
        }
    }

    /// "Did you mean …?": the base form of a single inflected word with no own headword (P1, PD-14); nil for phrases.
    public func baseForm(of text: String) -> String? {
        guard !TextKey.isPhrase(text) else { return nil }
        return (try? dictionary?.resolve(text))?.baseForms.first?.headword.text
    }

    /// Dictionary phrases inside a typed sentence ("looked after" → "look after").
    public func containedPhrases(in text: String) -> [String] {
        ((try? dictionary?.containedPhrases(in: text)) ?? []).map(\.text)
    }

    /// Related headwords of the word's headword (or of its base form), at most `limit` (P1, §6.2 item 8).
    public func related(to word: String, limit: Int) -> [Completion] {
        guard let dictionary else { return [] }
        let key = TextKey.matchKey(word)
        let id = (try? dictionary.headwords(key: key).first?.id)
            ?? (TextKey.isPhrase(word) ? nil : (try? dictionary.baseForms(of: key).first?.headword.id))
        guard let id else { return [] }
        return ((try? dictionary.related(to: id, limit: limit)) ?? []).map { Self.row($0.headword) }
    }

    /// What a one-tap add of a dictionary row saves: the headword's rank-1 variant with that sense's gloss and the
    /// dictionary provenance (version, headword key, sense ordinal). Nil when the word has no Russian variant.
    public func primarySense(of row: Completion) -> NewSense? {
        guard let dictionary, let headwords = try? dictionary.headwords(key: TextKey.matchKey(row.text)),
              let hw = headwords.first(where: { $0.partOfSpeech == row.partOfSpeech }) ?? headwords.first,
              let t = hw.translations.min(by: { $0.rank < $1.rank }) else { return nil }
        let gloss = hw.senses.first { $0.ordinal == t.senseOrdinal }?.glossEn
        return NewSense(translation: t.text, definition: gloss, partOfSpeech: hw.partOfSpeech, source: .wiktionary,
                        dictVersion: dictionary.version, dictHeadwordKey: hw.key, dictSenseOrdinal: t.senseOrdinal)
    }

    private static func row(_ c: ToriDictionary.Completion) -> Completion {
        Completion(text: c.text, partOfSpeech: c.partOfSpeech, translation: c.primaryTranslation)
    }
}
