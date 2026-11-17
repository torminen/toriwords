import Foundation
import Testing
import ToriCore
import ToriStore
@testable import ToriEnrichment

private func wiki(_ t: String) -> Suggestion { Suggestion(NewSense(translation: t, source: .wiktionary)) }
private func machine(_ t: String) -> Suggestion { Suggestion(NewSense(translation: t, source: .mtApple)) }

@Test func autocompleteClassifiesInput() {
    #expect(Autocomplete.classify(" m ") == .tooShort)
    #expect(Autocomplete.classify("mo") == .english("mo"))
    #expect(Autocomplete.classify("ёлка ") == .russian("ёлка"))
    #expect(Autocomplete.classify("ёлка tree") == .english("ёлка tree"))
}

@Test func autocompleteListsSavedFirstThenNewDictionaryKeysUpToEight() {
    let id = ToriID.settings
    let saved = (0..<4).map { Completion(text: "mort\($0)", entry: id) }
    let dict = [Completion(text: "Mort0")] + (10..<20).map { Completion(text: "mort\($0)") }
    let out = Autocomplete.merge(vocabulary: saved, dictionary: dict)
    #expect(out.count == 8)
    #expect(out.prefix(3).allSatisfy { $0.entry != nil })
    #expect(out[3].text == "mort10") // "Mort0" is already listed as a saved word.
}

@Test func newWordPreselectsFirstVariantAndSavesCheckedOnes() {
    var d = AddDraft(text: "  thorough ")
    d.setSuggestions([wiki("тщательный"), wiki("Тщательный"), machine("основательный")])
    #expect(d.variants.map(\.isChecked) == [true, false])
    #expect(d.variants[1].isMachine)
    d.toggle(1)
    d.ownTranslation = " дотошный "
    d.sentence = "A thorough search."
    d.source = " The Bear "
    d.tags = ["work", "  "]
    let input = d.captureInput(now: 42)
    #expect(input.term == "thorough")
    #expect(input.senses.map(\.translation) == ["тщательный", "основательный", "дотошный"])
    #expect(input.senses.last?.source == .user)
    #expect(input.highlight == Capture.Highlight(offset: 2, length: 8))
    #expect(input.source == SourceInput(kind: .other, title: "The Bear"))
    #expect(input.tags == ["work"])
}

@Test func savedWordShowsExistingMeaningsLockedAndPreselectsNothing() {
    var d = AddDraft(text: "bank")
    d.setSuggestions([wiki("берег"), wiki("банк")], existing: ["банк"], existingEntry: .settings)
    #expect(d.variants.map(\.sense.translation) == ["банк", "берег"])
    #expect(d.variants.map(\.isChecked) == [true, false])
    d.toggle(0)
    #expect(d.variants[0].isChecked)
    #expect(d.captureInput(now: 0).senses.isEmpty)
    #expect(d.captureInput(now: 0).sentence == nil && d.captureInput(now: 0).source == nil)
}

@Test func saveNeedsLatinLettersAndLongTextOffersPicking() {
    #expect(!AddDraft(text: " ... ").canSave)
    #expect(!AddDraft(text: "ёлка").canSave)
    #expect(AddDraft(text: "take off").canSave)
    #expect(!AddDraft(text: "take off").looksLikeSentence)
    var d = AddDraft(text: "The plane took off late.")
    #expect(d.looksLikeSentence)
    d.pick(firstChip: 2, lastChip: 3)
    #expect(d.text == "took off")
    #expect(d.sentence == "The plane took off late.")
    #expect(d.captureInput(now: 0).highlight == Capture.Highlight(offset: 10, length: 8))
}
