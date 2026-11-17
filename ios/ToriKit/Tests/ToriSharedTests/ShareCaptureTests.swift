import Foundation
import Testing
import ToriCore
@testable import ToriShared

@Test func payloadPrefersSafariSelectionAndReadsURLOnlyText() {
    let js = SharePayload(javaScript: ["selection": " took off ", "title": "Flights", "url": "https://www.theguardian.com/x",
                                       "sentence": "The plane took off an hour late."], texts: ["ignored"], urls: [])
    #expect(js.text == "took off" && js.title == "Flights" && js.fromSafari)
    #expect(js.domain == "theguardian.com" && js.sourceLabel == "Safari · theguardian.com")

    let link = SharePayload(javaScript: nil, texts: ["https://example.com/a"], urls: [])
    #expect(link.text == nil && link.url == "https://example.com/a" && link.sourceLabel == "example.com")

    let plain = SharePayload(javaScript: nil, texts: ["  ", "mortgage"], urls: ["https://bank.example/rates"])
    #expect(plain.text == "mortgage" && plain.url == "https://bank.example/rates" && !plain.fromSafari)
    #expect(SharePayload(javaScript: nil, texts: [], urls: []).sourceLabel == nil)
}

@Test func termSourceTakesSafariSentenceWithHighlight() throws {
    let p = SharePayload(text: "took off", url: "https://a.example", sentence: "Late again. The plane took off an hour late!",
                         fromSafari: true)
    let d = CaptureDraft(p)
    #expect(!d.isSentenceSource && d.term == "took off" && d.canSave)
    let s = try #require(d.sentence)
    let h = try #require(d.highlight)
    #expect(s == "The plane took off an hour late!")
    #expect((s as NSString).substring(with: NSRange(location: h.offset, length: h.length)) == "took off")

    let missing = CaptureDraft(SharePayload(text: "runway", sentence: "The plane took off."))
    #expect(missing.sentence == "The plane took off." && missing.highlight == nil)
}

@Test func sentenceSourcePicksChipsIntoAPhrase() throws {
    var d = CaptureDraft(SharePayload(text: "She looked after her little brother all summer long."))
    #expect(d.isSentenceSource && d.term == nil && !d.canSave)
    let i = try #require(d.chips.firstIndex(of: "looked"))
    d.tapChip(i)
    d.tapChip(i + 1)
    #expect(d.term == "looked after" && d.canSave)
    #expect(d.highlight == Capture.Highlight(offset: 4, length: 12))
    d.tapChip(i)          // picked end chip shrinks
    #expect(d.term == "after")
    d.tapChip(i + 1)      // the single picked chip unpicks
    #expect(d.term == nil && d.sentence == nil)
    d.tapChip(0); d.tapChip(5)  // a far chip starts a new pick
    #expect(d.selection == 5...5)
}

@Test func nonLatinTextBlocksSaveUntilEdited() {
    var d = CaptureDraft(SharePayload(text: "привет"))
    #expect(!d.canSave)
    d.editText("hello")
    #expect(d.canSave && d.term == "hello")
}

@Test func typedSentenceGetsFirstOccurrenceHighlight() {
    var d = CaptureDraft(SharePayload(url: "https://a.example"))
    #expect(d.term == nil)
    d.editText("Mortgage")
    d.editSentence("We paid off the mortgage early.")
    #expect(d.highlight == Capture.Highlight(offset: 16, length: 8))
    d.editSentence("  ")
    #expect(d.sentence == nil && d.highlight == nil)
}

@Test func inboxFileCarriesSourceTagsAndChoices() throws {
    let p = SharePayload(text: "take off", url: "https://a.example", fromSafari: true)
    let d = CaptureDraft(p)
    let chosen = InboxFile.ChosenSense(translation: "взлетать", pos: "verb",
                                       provenance: .init(kind: "wiktionary", dictVersion: "v", headwordKey: "take off", senseOrdinal: 1))
    let id = ToriID("0193a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b")!
    let f = try #require(d.inboxFile(captureId: id, capturedAt: 5, utcOffsetMin: 180, payload: p, sourceTitle: " Flights ",
                                     tags: ["work"], chosenSenses: [chosen], typedTranslation: "  ", resume: true))
    #expect(f.term == "take off" && f.origin == "shared" && f.resume && f.typedTranslation == nil)
    #expect(f.source == InboxFile.Source(url: "https://a.example", title: "Flights", app: "Safari"))
    #expect(f.tags == ["work"] && f.chosenSenses == [chosen] && f.sentence == nil && f.highlight == nil)
    let noSource = d.inboxFile(captureId: id, capturedAt: 5, utcOffsetMin: 0, payload: SharePayload(text: "take off"),
                               sourceTitle: "", tags: [], chosenSenses: [], typedTranslation: nil, resume: false)
    #expect(noSource?.source == nil && noSource?.tags == nil)
    #expect(CaptureDraft(SharePayload()).inboxFile(captureId: id, capturedAt: 0, utcOffsetMin: 0, payload: SharePayload(),
                                                   sourceTitle: nil, tags: [], chosenSenses: [], typedTranslation: nil,
                                                   resume: false) == nil)
}

@Test func tagsAndStickyRules() {
    #expect(TagInput.names(" work, Work ,, travel ") == ["work", "travel"])
    #expect(TagInput.suggestions(sticky: ["Work"], index: [.init(key: "work", name: "work"), .init(key: "home", name: "Home")])
            == ["Work", "Home"])
    let tip = CaptureSticky.tipShown(previous: nil)
    #expect(tip.tipShown && tip.offered(now: 1).sourceTitle == nil)
    let saved = CaptureSticky.afterSave(now: 100, sourceTitle: " ", tags: ["work"], previous: tip)
    #expect(saved.tipShown && saved.sourceTitle == nil && saved.offered(now: 100 + CaptureSticky.offerWindowMs).tags == ["work"])
    #expect(!CaptureSticky.afterSave(now: 1, sourceTitle: "x", tags: [], previous: nil).tipShown)
}

@Test func baseFormIsPreselectedAndCapturedFormStaysAvailable() throws {
    var d = CaptureDraft(SharePayload(text: "took", sentence: "The plane took off late."))
    d.setOffers(baseForm: "take", phrases: [])
    #expect(d.savedAs == "take" && d.entryText == "take" && d.term == "took")
    let id = ToriID("0193a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b")!
    let f = try #require(d.inboxFile(captureId: id, capturedAt: 1, utcOffsetMin: 0, payload: SharePayload(), sourceTitle: nil,
                                     tags: [], chosenSenses: [], typedTranslation: nil, resume: false))
    // The sentence keeps the captured span highlighted.
    #expect(f.term == "take" && f.sentence == "The plane took off late." && f.highlight == Capture.Highlight(offset: 10, length: 4))
    d.saveAs(nil)
    #expect(d.entryText == "took")
    d.saveAs("bogus")
    #expect(d.savedAs == nil)
}

@Test func phraseOffersArePickedExplicitlyAndResetOnANewPick() throws {
    var d = CaptureDraft(SharePayload(text: "She looked after her little brother all summer long."))
    let i = try #require(d.chips.firstIndex(of: "looked"))
    d.tapChip(i); d.tapChip(i + 1)
    d.setOffers(baseForm: nil, phrases: ["look after", "Looked after", "look after"])
    #expect(d.phrases == ["look after"] && d.savedAs == nil && d.entryText == "looked after")
    d.saveAs("look after")
    #expect(d.entryText == "look after" && d.sentence != nil)
    d.tapChip(i + 3)
    #expect(d.phrases.isEmpty)
    #expect(d.savedAs == nil)
    #expect(d.entryText == "little")
}

@Test func offersEqualToTheCapturedTextAreDropped() {
    var d = CaptureDraft(SharePayload(text: "Run"))
    d.setOffers(baseForm: "run", phrases: [])
    #expect(d.baseForm == nil && d.entryText == "Run")
    var empty = CaptureDraft(SharePayload())
    empty.setOffers(baseForm: "take", phrases: ["take off"])
    #expect(empty.baseForm == nil && empty.phrases.isEmpty && empty.entryText == nil)
}
