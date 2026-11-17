import Testing
@testable import ToriCore

private func id(_ n: UInt64) -> ToriID { ToriID(high: 0, low: n) }
private func card(_ n: UInt64, entry: UInt64? = nil) -> ReviewSession.Card { .init(id: id(n), entry: id(entry ?? n + 100)) }

private extension ReviewSession {
    var ids: [UInt64] { remaining.map(\.id.low) }
    mutating func grade(_ r: Rating, at t: Int64 = 1_000, shownAt: Int64 = 0) -> Answer? {
        answer(r, at: t, utcOffsetMin: 60, shownAt: shownAt)
    }
}

@Test func answerHoldsOneUncommittedAnswerAndCommitsThePreviousOne() {
    var s = ReviewSession(cards: [card(1), card(2), card(3)], newEntries: [])
    #expect(s.position == 1 && s.total == 3 && !s.canUndo)
    #expect(s.grade(.remembered) == nil)
    #expect(s.canUndo)
    #expect(s.current?.id == id(2))
    #expect(s.position == 2 && s.total == 3)
    let committed = s.grade(.remembered)
    #expect(committed?.card.id == id(1))
    #expect(committed?.utcOffsetMin == 60)
    #expect(s.pending?.card.id == id(2))
}

@Test func undoBringsTheCardBackAndDropsTheAnswer() {
    var s = ReviewSession(cards: [card(1), card(2), card(3), card(4), card(5)], newEntries: [])
    _ = s.grade(.remembered)
    _ = s.grade(.forgot) // card 2 re-shown after 3 cards
    #expect(s.ids == [3, 4, 5, 2])
    s.undo()
    #expect(s.ids == [2, 3, 4, 5])
    #expect(!s.canUndo)
    #expect(s.position == 2)
    // Only the uncommitted answer can be undone; card 1 stays answered.
    s.undo()
    #expect(s.ids == [2, 3, 4, 5])
    #expect(s.flush() == nil)
}

@Test func forgotReshowIsPlacedAFewCardsLaterOrLast() {
    var s = ReviewSession(cards: [card(1), card(2)], newEntries: [])
    _ = s.grade(.forgot)
    #expect(s.ids == [2, 1])
    _ = s.grade(.remembered)
    _ = s.grade(.forgot)
    #expect(s.ids == [1])
    #expect(s.total == 4)
}

@Test func answerMsIsCappedAtTenMinutes() {
    var s = ReviewSession(cards: [card(1), card(2)], newEntries: [])
    _ = s.grade(.remembered, at: 1_000_000, shownAt: 0)
    #expect(s.pending?.answerMs == 600_000)
    _ = s.grade(.remembered, at: 1_000_500, shownAt: 1_000_000)
    #expect(s.pending?.answerMs == 500)
}

@Test func summaryCountsFirstAnswersAndNewEntries() {
    // Cards 1 and 2 belong to new entry 50; card 3 to an old entry.
    var s = ReviewSession(cards: [card(1, entry: 50), card(3, entry: 60), card(2, entry: 50)], newEntries: [id(50)])
    _ = s.grade(.forgot)     // 1 forgot → re-shown last
    _ = s.grade(.remembered) // 3
    _ = s.grade(.remembered) // 2
    _ = s.grade(.remembered) // 1 again
    #expect(s.isFinished)
    _ = s.flush()
    #expect(s.summary == .init(reviewed: 3, remembered: 2, newWords: 1))
}

@Test func removeEntryAndLearnMore() {
    var s = ReviewSession(cards: [card(1, entry: 50), card(2, entry: 60), card(3, entry: 50)], newEntries: [])
    s.remove(entry: id(50))
    #expect(s.ids == [2])
    s.append([card(2, entry: 60), card(7)])
    #expect(s.ids == [2, 7])
}

@Test func sentenceRotation() {
    let c = { (n: UInt64, at: Int64, s: Bool, h: Bool) in
        SentenceRotation.Context(id: id(n), capturedAt: at, hasSentence: s, hasHighlight: h)
    }
    let contexts = [c(3, 20, true, false), c(1, 10, true, true), c(2, 10, true, true), c(4, 5, false, false)]
    #expect(SentenceRotation.pick(contexts, reps: 0, needsHighlight: false) == id(1))
    #expect(SentenceRotation.pick(contexts, reps: 2, needsHighlight: false) == id(3))
    #expect(SentenceRotation.pick(contexts, reps: 3, needsHighlight: false) == id(1))
    #expect(SentenceRotation.pick(contexts, reps: 1, needsHighlight: true) == id(2))
    #expect(SentenceRotation.pick(contexts, reps: 2, needsHighlight: true) == id(1))
    #expect(SentenceRotation.pick([c(4, 5, false, false)], reps: 0, needsHighlight: false) == nil)
}
