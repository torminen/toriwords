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
