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

// MARK: DictionarySearch (Add / Entry adapter)

@Test func searchCompletesAndReversesRussianFromTwoLetters() {
    let search = DictionarySearch(sampleDictionary)
    let rows = search.complete("Ma", limit: 8)
    #expect(rows.count == 8 && rows.allSatisfy { TextKey.matchKey($0.text).hasPrefix("ma") && $0.entry == nil })
    #expect(search.reverse("б", limit: 8).isEmpty)
    let ru = search.reverse("бег", limit: 8)
    #expect(ru.first?.text == "run" && ru.first?.translation?.hasPrefix("бег") == true)
    #expect(DictionarySearch(nil).complete("ma", limit: 8).isEmpty && DictionarySearch(nil).reverse("бег", limit: 8).isEmpty)
}

@Test func searchOffersBaseFormAndContainedPhrases() {
    let search = DictionarySearch(sampleDictionary)
    #expect(search.baseForm(of: "Took") == "take")
    #expect(search.baseForm(of: "take") == nil)
    #expect(search.baseForm(of: "took off") == nil)
    #expect(search.containedPhrases(in: "She looked after her brother.") == ["look after"])
    #expect(DictionarySearch(nil).baseForm(of: "took") == nil)
}

@Test func relatedRowsAddWithDictionaryProvenance() throws {
    let search = DictionarySearch(sampleDictionary)
    let related = search.related(to: "Actually", limit: 8)
    #expect(!related.isEmpty && related.count <= 8)
    #expect(search.related(to: "zzzz", limit: 8).isEmpty && DictionarySearch(nil).related(to: "actually", limit: 8).isEmpty)
    let row = try #require(related.first { $0.translation != nil })
    let sense = try #require(search.primarySense(of: row))
    #expect(sense.translation == row.translation && sense.definition != nil)
    #expect(sense.source == .wiktionary && sense.dictVersion == sampleDictionary.version
            && sense.dictHeadwordKey == TextKey.matchKey(row.text))
}
