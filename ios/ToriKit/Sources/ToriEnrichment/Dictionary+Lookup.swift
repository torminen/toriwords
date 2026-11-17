import ToriDictionary

extension BundledDictionary: DictionaryLookup {
    /// Headwords for the key; each sense carries its RU variants by rank, and variants not tied to a sense come as a
    /// last sense with `ordinal` nil and no gloss.
    public func lookup(key: String) throws -> [DictionaryHeadword] {
        try headwords(key: key).map { hw in
            var senses = hw.senses.map { s in
                DictionarySense(ordinal: s.ordinal, glossEn: s.glossEn,
                                translationsRu: hw.translations.filter { $0.senseOrdinal == s.ordinal }.map(\.text))
            }
            let loose = hw.translations.filter { $0.senseOrdinal == nil }.map(\.text)
            if !loose.isEmpty { senses.append(DictionarySense(ordinal: nil, glossEn: nil, translationsRu: loose)) }
            return DictionaryHeadword(text: hw.text, key: hw.key, partOfSpeech: hw.partOfSpeech, ipa: hw.ipa, senses: senses)
        }
    }
}
