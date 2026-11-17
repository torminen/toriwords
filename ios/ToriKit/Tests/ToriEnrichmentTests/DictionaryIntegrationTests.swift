import Foundation
import Testing
import ToriCore
import ToriDictionary
import ToriStore
@testable import ToriEnrichment

let sampleDictionary = try! BundledDictionary(path: URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/dictionary-sample.sqlite").path)

@Test func lookupMapsSenseVariantsAndLooseVariantsLast() throws {
    let hw = try #require(try sampleDictionary.lookup(key: "look after").first)
    #expect(hw.senses.dropLast().allSatisfy { $0.ordinal != nil && $0.glossEn != nil })
    let loose = try #require(hw.senses.last)
    #expect(loose.ordinal == nil && loose.glossEn == nil && loose.translationsRu.contains("заботиться, приглядывать"))
    let suggestions = Suggestions.build(headwords: [hw], dictVersion: sampleDictionary.version, machine: nil)
    #expect(suggestions.first?.sense.dictSenseOrdinal != nil)
    #expect(suggestions.last?.sense.dictSenseOrdinal == nil)
    #expect(suggestions.last?.sense.translation == "заботиться, приглядывать")
    #expect(Set(suggestions.map { TextKey.translationKey($0.sense.translation ?? "") }).count == suggestions.count)
}

@Test func headwordWithoutSensesStillSuggestsItsVariants() {
    let hw = DictionaryHeadword(text: "x", key: "x", partOfSpeech: nil, ipa: nil, senses: [
        DictionarySense(ordinal: nil, glossEn: nil, translationsRu: ["б"]),
        DictionarySense(ordinal: 2, glossEn: "g", translationsRu: ["а"]),
    ])
    #expect(Suggestions.build(headwords: [hw], dictVersion: "v", machine: nil).map(\.sense.translation) == ["а", "б"])
}

@Test func autocompleteMergesVocabularyFirstAndCapsAtEight() throws {
    let h = try Harness()
    _ = try h.capture("Make")
    _ = try h.capture("man")
    #expect(try Autocomplete.items(for: "m", store: h.store, dictionary: sampleDictionary).isEmpty)
    let items = try Autocomplete.items(for: "Ma", store: h.store, dictionary: sampleDictionary)
    #expect(items.count == 8)
    guard case .vocabulary(let a) = items[0], case .vocabulary(let b) = items[1] else { Issue.record("vocabulary first"); return }
    #expect([a.matchKey, b.matchKey] == ["make", "man"])
    let dictKeys = items.dropFirst(2).compactMap { if case .dictionary(let c) = $0 { c.key } else { nil } }
    #expect(dictKeys.count == 6 && !dictKeys.contains("make") && !dictKeys.contains("man"))
    // Without a dictionary only the vocabulary part remains.
    #expect(try Autocomplete.items(for: "ma", store: h.store, dictionary: nil).count == 2)
}

@Test func vocabularyPrefixIsCappedAndIgnoresDeletedEntries() throws {
    let h = try Harness()
    var ids: [String: ToriID] = [:]
    for t in ["tab", "table", "tablet", "taboo"] { ids[t] = try h.capture(t) }
    let hits = try h.store.read { try $0.vocabularyPrefix("tab") }
    #expect(hits.map(\.matchKey) == ["tab", "table", "tablet"])
    try h.store.deleteEntries([ids["table"]!])
    #expect(try h.store.read { try $0.vocabularyPrefix("tab", limit: 8) }.map(\.text) == ["tab", "tablet", "taboo"])
}
