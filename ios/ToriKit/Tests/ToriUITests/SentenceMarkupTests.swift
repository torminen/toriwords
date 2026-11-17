import Testing
import ToriCore
import ToriUI

@Test func splitsByUTF16Range() throws {
    let s = "The police carried out a thorough search."
    let m = try #require(SentenceMarkup(sentence: s, highlight: .init(offset: 25, length: 8)))
    #expect(m.word == "thorough")
    #expect(m.before + m.word + m.after == s)
    #expect(m.blanked == "The police carried out a ______ search.")
}

@Test func countsEmojiAndAccentsInUTF16Units() throws {
    // "👍" is 2 UTF-16 units; "é" (precomposed) is 1.
    let m = try #require(SentenceMarkup(sentence: "👍 café bleak", highlight: .init(offset: 8, length: 5)))
    #expect(m.word == "bleak")
    #expect(m.before == "👍 café ")
}

@Test func rejectsInvalidRanges() {
    #expect(SentenceMarkup(sentence: "bleak", highlight: nil) == nil)
    #expect(SentenceMarkup(sentence: "bleak", highlight: .init(offset: 3, length: 5)) == nil)
    #expect(SentenceMarkup(sentence: "bleak", highlight: .init(offset: 0, length: 0)) == nil)
    // Inside a surrogate pair.
    #expect(SentenceMarkup(sentence: "👍 hi", highlight: .init(offset: 1, length: 2)) == nil)
}
