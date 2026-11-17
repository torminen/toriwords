import Testing
import ToriCore
import ToriTestSupport

@Test(arguments: Fixture.cases("capture/clean.json"))
func captureClean(_ c: FixtureCase) {
    let r = Capture.clean(c["input"].string!), e = c["expected"]
    #expect(sameScalars(r.text, e["text"].string))
    #expect(r.kind.rawValue == e["kind"].string)
    #expect(r.isSaveable == e["saveable"].bool)
}

@Test(arguments: Fixture.cases("capture/extract.json"))
func captureExtract(_ c: FixtureCase) {
    let chips = c["chosenChips"].array.map(\.int!)
    let r = Capture.extract(Capture.clean(c["input"].string!), firstChip: chips[0], lastChip: chips[1])
    let e = c["expected"]
    #expect(sameScalars(r.entryText, e["entryText"].string))
    #expect(sameScalars(r.sentence, e["sentence"].string))
    #expect(r.highlight == Capture.Highlight(offset: e["highlight"]["offset"].int!, length: e["highlight"]["length"].int!))
    #expect(r.sentence.unicodeScalars.count <= Capture.maxSentence)
}

@Test(arguments: Fixture.cases("capture/typed-highlight.json"))
func captureTypedHighlight(_ c: FixtureCase) {
    let r = Capture.typedHighlight(sentence: c["sentence"].string!, entryText: c["entryText"].string!)
    let e = c["expected"]
    #expect(r == (e.isNull ? nil : Capture.Highlight(offset: e["offset"].int!, length: e["length"].int!)))
}
