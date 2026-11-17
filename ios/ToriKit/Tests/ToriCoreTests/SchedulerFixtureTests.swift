import Foundation
import Testing
import ToriCore
import ToriTestSupport

func parameters(_ file: JSON) -> FSRSParameters {
    let p = file["params"]
    return FSRSParameters(w: p["w"].array.map(\.double!), desiredRetention: p["desiredRetention"].double!,
                          maximumInterval: p["maximumInterval"].int!)
}

func id(_ j: JSON) -> ToriID { ToriID(j.string!)! }

/// S and D within 1e-9 relative; everything else exact.
func expectState(_ s: CardState?, _ e: JSON, sourceLocation: SourceLocation = #_sourceLocation) {
    guard let s else {
        #expect(e.isNull, sourceLocation: sourceLocation)
        return
    }
    func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-9 * max(abs(a), abs(b)) }
    #expect(close(s.stability, e["stability"].double!), "S \(s.stability)", sourceLocation: sourceLocation)
    #expect(close(s.difficulty, e["difficulty"].double!), "D \(s.difficulty)", sourceLocation: sourceLocation)
    #expect(s.lastReviewDay == e["lastReviewDay"].int, sourceLocation: sourceLocation)
    #expect(s.dueDay == e["dueDay"].int, sourceLocation: sourceLocation)
    #expect(s.interval == e["interval"].int, sourceLocation: sourceLocation)
    #expect(s.reps == e["reps"].int, sourceLocation: sourceLocation)
    #expect(s.lapses == e["lapses"].int, sourceLocation: sourceLocation)
    #expect(s.stage.rawValue == e["stage"].string, sourceLocation: sourceLocation)
}

@Test func defaultParametersMatchFixtures() {
    #expect(FSRSParameters.default == parameters(Fixture.file("scheduler/fsrs-step.json")))
}

@Test(arguments: Fixture.cases("scheduler/day-boundary.json"))
func dayBoundary(_ c: FixtureCase) {
    #expect(DayModel.dayNumber(unixMs: c["tMs"].int64!, utcOffsetMin: c["utcOffsetMin"].int!) == c["expected"].int)
}

@Test(arguments: Fixture.cases("scheduler/fsrs-step.json"))
func fsrsStep(_ c: FixtureCase) {
    let p = c["state"]
    let prev = p.isNull ? nil : CardState(
        stability: p["stability"].double!, difficulty: p["difficulty"].double!, lastReviewDay: p["lastReviewDay"].int!,
        dueDay: p["lastReviewDay"].int!, reps: p["reps"].int!, lapses: p["lapses"].int!, lastRating: .remembered, interval: nil)
    let s = FSRS.step(prev, cardID: id(c["cardId"]), day: c["reviewDay"].int!, rating: Rating(rawValue: c["rating"].int!)!,
                      parameters(c.file))
    expectState(s, c["expected"])
}

func log(_ j: JSON, card: ToriID? = nil) -> ReviewLogInput {
    ReviewLogInput(id: id(j["id"]), cardID: card ?? id(j["cardId"]), reviewedAt: j["reviewedAt"].int64!,
                   utcOffsetMin: j["utcOffsetMin"].int!, rating: j["rating"].int.flatMap(Rating.init))
}

@Test(arguments: Fixture.cases("scheduler/fsrs-replay.json"))
func fsrsReplay(_ c: FixtureCase) {
    let card = id(c["cardId"]), p = parameters(c.file)
    let logs = c["logs"].array.map { log($0, card: card) }
    let rated = logs.sorted(by: ReviewLogInput.replayOrder).filter { $0.rating != nil }
    let steps = c["expected"]["steps"].array
    #expect(rated.map(\.id.description) == steps.map { $0["logId"].string! })
    var state: CardState?
    for (l, e) in zip(rated, steps) {
        #expect(l.reviewDay == e["reviewDay"].int)
        state = FSRS.step(state, cardID: card, day: l.reviewDay, rating: l.rating!, p)
        expectState(state, e)
    }
    expectState(FSRS.replay(cardID: card, logs: logs, p), c["expected"]["final"])
}

struct QueueInput {
    var entries: [QueueEntry]
    var logs: [ReviewLogInput]
    var now: Int64
    var offset: Int
    var newWordsPerDay: Int

    init(_ j: JSON) {
        entries = j["entries"].array.map { e in
            QueueEntry(id: id(e["id"]), createdAt: e["createdAt"].int64!, isActive: e["status"].string == "active",
                       cards: e["cards"].array.map { QueueCard(id: id($0["id"]), direction: CardDirection(rawValue: $0["direction"].string!)!) })
        }
        logs = j["logs"].array.map { log($0) }
        now = j["now"].int64!
        offset = j["utcOffsetMin"].int!
        newWordsPerDay = j["settings"]["newWordsPerDay"].int!
    }
}

let queueFiles = ["queue-basic", "queue-new-limit", "queue-reshow", "queue-new-answered-today", "queue-catchup"]

@Test(arguments: queueFiles.flatMap { Fixture.cases("scheduler/\($0).json") })
func dailyQueue(_ c: FixtureCase) {
    let i = QueueInput(c["input"])
    let q = DailyQueue.build(entries: i.entries, logs: i.logs, today: DayModel.dayNumber(unixMs: i.now, utcOffsetMin: i.offset),
                             newWordsPerDay: i.newWordsPerDay, parameters: parameters(c.file))
    let e = c["expected"]
    func ids(_ j: JSON) -> [String] { j.array.map(\.string!) }
    #expect(q.reviews.map(\.description) == ids(e["reviews"]))
    #expect(q.new.map(\.description) == ids(e["new"]))
    #expect(q.reshow.map(\.description) == ids(e["reshow"]))
    #expect(q.toReviewCount == e["dueToday"]["toReview"].int)
    #expect(q.newCount == e["dueToday"]["new"].int)
    #expect(q.waiting == e["waiting"].int)
    #expect(q.catchUp == e["catchUp"].bool)
    #expect(q.normalLoad == e["normalLoad"].int)
    #expect(q.homeState.rawValue == e["homeState"].string)
}

@Test(arguments: Fixture.cases("scheduler/snapshot.json"))
func widgetSnapshot(_ c: FixtureCase) throws {
    let i = QueueInput(c["input"])
    let s = WidgetSnapshot.compute(entries: i.entries, logs: i.logs, now: i.now, utcOffsetMin: i.offset,
                                   newWordsPerDay: i.newWordsPerDay, parameters: parameters(c.file))
    let actual = try JSONDecoder().decode(JSON.self, from: JSONEncoder().encode(s))
    let expected = c["expected"]
    // nextDueDay null is encoded by omission; compare field by field.
    for key in ["format", "generatedAt", "utcOffsetMin", "days", "homeState", "nextDueDay"] {
        #expect(actual[key] == expected[key], "\(key)")
    }
}
