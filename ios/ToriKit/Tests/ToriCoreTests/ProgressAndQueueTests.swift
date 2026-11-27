import Testing
import ToriCore

private let offset = 180
private let today = 20774
/// Unix ms of 10:00 local on `day` (UTC+3).
private func at(_ day: Int, hour: Int = 10) -> Int64 { Int64(day * 86400 + hour * 3600 - offset * 60) * 1000 }
private func uid(_ n: UInt64) -> ToriID { ToriID.v7(unixMs: 1_700_000_000_000, randA: 0, randB: n) }

private func entry(_ n: UInt64, created: Int, active: Bool = true, directions: [CardDirection] = [.recognition]) -> QueueEntry {
    let e = uid(n)
    return QueueEntry(id: e, createdAt: at(created), isActive: active,
                      cards: directions.map { QueueCard(id: ToriID.card(entry: e, direction: $0), direction: $0) })
}

private func review(_ card: QueueCard, _ day: Int, _ rating: Rating, n: UInt64) -> ReviewLogInput {
    ReviewLogInput(id: uid(1000 + n), cardID: card.id, reviewedAt: at(day), utcOffsetMin: offset, rating: rating)
}

@Test func entryStageRule() {
    let learning = CardState(stability: 5, difficulty: 5, lastReviewDay: 0, dueDay: 5, reps: 1, lapses: 0, lastRating: .remembered, interval: 5)
    var known = learning
    known.stability = 30
    #expect(entryStage(cardStates: []) == .new)
    #expect(entryStage(cardStates: [nil, nil]) == .new)
    #expect(entryStage(cardStates: [known, nil]) == .learning)
    #expect(entryStage(cardStates: [known, learning]) == .learning)
    #expect(entryStage(cardStates: [known, known]) == .knownWell)
    known.lastRating = .forgot
    #expect(entryStage(cardStates: [known]) == .learning)
}

@Test func learnMoreAddsBatchesPastTheLimit() {
    let entries = (1...5).map { entry($0, created: today - 10 + Int($0)) }
    let base = DailyQueue.build(entries: entries, logs: [], today: today, newWordsPerDay: 2)
    #expect(base.new == entries.prefix(2).map(\.cards[0].id))
    #expect(base.canLearnMore)
    let more = DailyQueue.build(entries: entries, logs: [], today: today, newWordsPerDay: 2,
                                extensions: QueueExtensions(extraNewBatches: 1))
    #expect(more.new == entries.prefix(4).map(\.cards[0].id))
    let all = DailyQueue.build(entries: entries, logs: [], today: today, newWordsPerDay: 2,
                               extensions: QueueExtensions(extraNewBatches: 2))
    #expect(all.new.count == 5)
    #expect(!all.canLearnMore)
    #expect(!DailyQueue.build(entries: entries, logs: [], today: today, newWordsPerDay: 0).canLearnMore)
}

@Test func reviewAllIgnoresTheCatchUpQuota() {
    let entries = (1...150).map { entry($0, created: today - 40) }
    let logs = entries.enumerated().map { review($1.cards[0], today - 30, .remembered, n: UInt64($0)) }
    let capped = DailyQueue.build(entries: entries, logs: logs, today: today, newWordsPerDay: 10)
    #expect(capped.catchUp && capped.reviews.count == 84)
    let all = DailyQueue.build(entries: entries, logs: logs, today: today, newWordsPerDay: 10,
                               extensions: QueueExtensions(reviewAll: true))
    #expect(all.reviews.count == 150)
    #expect(all.sessionOrder == all.reviews)
}

@Test func progressToday() {
    let e1 = entry(1, created: today - 5), e2 = entry(2, created: today - 5, directions: [.recognition, .recall])
    let logs = [review(e1.cards[0], today - 3, .remembered, n: 1), review(e1.cards[0], today, .remembered, n: 2),
                review(e2.cards[0], today, .forgot, n: 3)]
    let t = ProgressStats.today(DailyQueue.build(entries: [e1, e2], logs: logs, today: today, newWordsPerDay: 10))
    #expect(t == ProgressStats.Today(cardsReviewed: 2, toReview: 1, new: 0, newWordsIntroduced: 1))
}

@Test func answeredTodayListsTodaysCardsOfActiveEntries() {
    let e1 = entry(1, created: today - 5), e2 = entry(2, created: today - 5), paused = entry(3, created: today - 5, active: false)
    let logs = [review(e1.cards[0], today - 3, .remembered, n: 1), review(e2.cards[0], today, .forgot, n: 2),
                review(e2.cards[0], today, .remembered, n: 3), review(paused.cards[0], today, .remembered, n: 4)]
    let q = DailyQueue.build(entries: [e1, e2, paused], logs: logs, today: today, newWordsPerDay: 10)
    #expect(q.answeredToday == [e2.cards[0].id])
}

@Test func progressVocabulary() {
    let v = ProgressStats.vocabulary([.active(.new), .active(.learning), .active(.learning), .active(.knownWell), .alreadyKnown, .paused])
    #expect(v == ProgressStats.Vocabulary(new: 1, learning: 2, knownWell: 1, alreadyKnown: 1, paused: 1))
}

@Test func progressActivityUsesEachLogsOwnReviewDay() {
    let card = QueueCard(id: uid(1), direction: .recognition)
    var logs = [review(card, today, .remembered, n: 1), review(card, today - 29, .hard, n: 2),
                review(card, today - 30, .easy, n: 3)]
    // 02:00 UTC on `today` is still yesterday at UTC+0 (before 04:00), but today at UTC+3.
    logs.append(ReviewLogInput(id: uid(9), cardID: card.id, reviewedAt: at(today, hour: 5), utcOffsetMin: 0, rating: .remembered))
    logs.append(ReviewLogInput(id: uid(10), cardID: card.id, reviewedAt: at(today), utcOffsetMin: offset, rating: nil))
    let a = ProgressStats.activity(logs: logs, today: today)
    #expect(a.count == 30)
    #expect(a[29] == 1 && a[28] == 1 && a[0] == 1 && a.reduce(0, +) == 3)
}

@Test func progressCapturedPerWeek() {
    let created = [at(today), at(today - 6), at(today - 7), at(today - 55), at(today - 56), at(today, hour: 3)]
    #expect(ProgressStats.capturedPerWeek(createdAt: created, today: today, utcOffsetMin: offset) == [1, 0, 0, 0, 0, 0, 1, 3])
}

@Test func progressTopSources() {
    func s(_ n: UInt64, _ title: String?, _ url: String?, _ count: Int, suggested: Bool = false) -> ProgressStats.SourceUsage {
        .init(id: uid(n), title: title, url: url, isSuggested: suggested, entryCount: count)
    }
    let top = ProgressStats.topSources([
        s(1, "The Bear S2", nil, 3), s(2, nil, "https://www.nytimes.com/2026/x", 5), s(3, "Suggested", nil, 9, suggested: true),
        s(5, "b", nil, 3), s(4, "b", nil, 3), s(6, "z", nil, 1), s(7, "zz", nil, 1), s(8, "none", nil, 0)])
    #expect(top.map(\.label) == ["nytimes.com", "The Bear S2", "b", "b", "z"])
    #expect(top[2].id == uid(4))
}

@Test func noneReviewableOnlyWhenAWordNeedsATranslation() {
    let paused = [entry(1, created: today - 5, active: false), entry(2, created: today - 4, active: false)]
    #expect(DailyQueue.build(entries: paused, logs: [], today: today, newWordsPerDay: 10).homeState == .nothingDue)
    let untranslated = entry(3, created: today - 3, directions: [])
    #expect(DailyQueue.build(entries: paused + [untranslated], logs: [], today: today, newWordsPerDay: 10).homeState == .noneReviewable)
}
