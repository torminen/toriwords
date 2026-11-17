import ToriCore

/// One RU variant to pick in the capture sheet (UI doc §3.3, checkboxes, first preselected).
public struct Variant: Hashable, Sendable {
    public var translation: String
    /// The gloss of the sense the variant belongs to; nil for variants not tied to a sense.
    public var glossEn: String?
    public var partOfSpeech: String
    public var headwordKey: String
    public var senseOrdinal: Int?

    /// Variants of the headwords in their order, each headword's by rank, without repeats by translation key.
    public static func of(_ headwords: [Headword]) -> [Variant] {
        var seen = Set<String>()
        return headwords.flatMap { hw in
            let gloss = Dictionary(hw.senses.map { ($0.ordinal, $0.glossEn) }, uniquingKeysWith: { a, _ in a })
            return hw.translations.compactMap { t -> Variant? in
                guard seen.insert(TextKey.translationKey(t.text)).inserted else { return nil }
                return Variant(translation: t.text, glossEn: t.senseOrdinal.flatMap { gloss[$0] },
                               partOfSpeech: hw.partOfSpeech, headwordKey: hw.key, senseOrdinal: t.senseOrdinal)
            }
        }
    }
}
