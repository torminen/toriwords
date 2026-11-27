/// A live Entry as the queue sees it: its live canonical Cards and whether it is `active`.
public struct QueueEntry: Hashable, Sendable {
    public var id: ToriID
    public var createdAt: Int64
    public var isActive: Bool
    public var cards: [QueueCard]

    public init(id: ToriID, createdAt: Int64, isActive: Bool, cards: [QueueCard]) {
        self.id = id
        self.createdAt = createdAt
        self.isActive = isActive
        self.cards = cards
    }
}

public struct QueueCard: Hashable, Sendable {
    public var id: ToriID
    public var direction: CardDirection

    public init(id: ToriID, direction: CardDirection) {
        self.id = id
        self.direction = direction
    }
}

/// Home "Due today" state.
public enum HomeState: String, Codable, Sendable {
    case due, allDone, nothingDue, noneReviewable, empty
}

/// Device-local, session-only extensions of today's list. Nothing is stored or synced.
public struct QueueExtensions: Hashable, Sendable {
    /// "Review all now": every waiting Card, ignoring the catch-up quota.
    public var reviewAll: Bool
    /// "Learn more new words": extra batches of `newWordsPerDay` New Entries past the limit (also in catch-up).
    public var extraNewBatches: Int

    public init(reviewAll: Bool = false, extraNewBatches: Int = 0) {
        self.reviewAll = reviewAll
        self.extraNewBatches = extraNewBatches
    }
}

/// Today's queue. Nothing about it is stored; build it from synced data and `today`.
public struct DailyQueue: Hashable, Sendable {
    /// Step 1: waiting Cards taken, in session order.
    public var reviews: [ToriID]
    /// Step 2: New Cards taken, in session order.
    public var new: [ToriID]
    /// Step 3: Cards whose latest answer today leaves them due today, by Card ID.
    public var reshow: [ToriID]
    public var waiting: Int
    public var catchUp: Bool
    public var normalLoad: Int
    public var homeState: HomeState
    /// Distinct Cards of active Entries with a rated log today (Progress → Today, practice), in Entry order.
    public var answeredToday: [ToriID]
    public var cardsAnsweredToday: Int { answeredToday.count }
    /// |introducedToday|: Entries with no rated log before today and at least one today.
    public var introducedToday: Int
    /// "Learn more new words" is offered: a New Entry is left untaken and `newWordsPerDay > 0`.
    public var canLearnMore: Bool

    /// "N to review" = steps 1 + 3.
    public var toReviewCount: Int { reviews.count + reshow.count }
    /// "M new" = step 2.
    public var newCount: Int { new.count }

    /// Session order when Review opens: reviews, then re-shows, then new Cards (the UI also inserts a re-show
    /// a few cards after each Forgot).
    public var sessionOrder: [ToriID] { reviews + reshow + new }

    public static func build(entries: [QueueEntry], logs: [ReviewLogInput], today: Int, newWordsPerDay: Int,
                             extensions: QueueExtensions = QueueExtensions(),
                             parameters: FSRSParameters = .default) -> DailyQueue {
        let active = entries.filter { $0.isActive && !$0.cards.isEmpty }
        var entryOf: [ToriID: ToriID] = [:]
        for e in active { for c in e.cards { entryOf[c.id] = e.id } }

        // Rated logs per Card, replay-sorted, with the state after each log.
        var byCard: [ToriID: [ReviewLogInput]] = [:]
        for l in logs where l.rating != nil && entryOf[l.cardID] != nil { byCard[l.cardID, default: []].append(l) }
        struct History { var days: [Int]; var states: [CardState] }
        var history: [ToriID: History] = [:]
        for (id, ls) in byCard {
            let sorted = ls.sorted(by: ReviewLogInput.replayOrder)
            var states: [CardState] = []
            for l in sorted { states.append(FSRS.step(states.last, cardID: id, day: l.reviewDay, rating: l.rating!, parameters)) }
            history[id] = History(days: sorted.map(\.reviewDay), states: states)
        }
        func hasBefore(_ id: ToriID, _ day: Int) -> Bool { history[id]?.days.contains { $0 < day } ?? false }
        func hasOn(_ id: ToriID, _ day: Int) -> Bool { history[id]?.days.contains(day) ?? false }

        let cards = active.flatMap(\.cards)
        let started = Set(cards.map(\.id).filter { hasBefore($0, today) })
        let reviewedToday = started.filter { hasOn($0, today) }
        let waiting = cards.map(\.id).filter { started.contains($0) && !hasOn($0, today) && history[$0]!.states.last!.dueDay <= today }
        var entryIsNew: [ToriID: Bool] = [:]
        for e in active { entryIsNew[e.id] = !e.cards.contains { hasBefore($0.id, today) } }
        let introducedToday = active.filter { entryIsNew[$0.id]! && $0.cards.contains { hasOn($0.id, today) } }.count
        let answeredToday = cards.filter { hasOn($0.id, today) }

        let reshow = answeredToday.compactMap { card -> ToriID? in
            let h = history[card.id]!
            let last = h.days.lastIndex(of: today)!
            return h.states[last].dueDay == today ? card.id : nil
        }.sorted()

        // Normal load and catch-up.
        let activeDays = Array(Set(history.values.flatMap(\.days).filter { $0 < today }).sorted(by: >).prefix(14))
        let pairCount = history.reduce(0) { sum, item in
            sum + Set(item.value.days.filter { activeDays.contains($0) && hasBefore(item.key, $0) }).count
        }
        let normalLoad = activeDays.isEmpty ? 50 : max(50, ceilDiv(pairCount, activeDays.count))
        let load = waiting.count + reviewedToday.count
        let catchUp = load > 2 * normalLoad
        let quota = catchUp && !extensions.reviewAll ? normalLoad + ceilDiv(load - normalLoad, 3) : Int.max

        var takenEntries = Set<ToriID>()
        let entriesWithLogToday = Set(answeredToday.map { entryOf[$0.id]! })
        func passes(_ id: ToriID) -> Bool {
            let e = entryOf[id]!
            return !entriesWithLogToday.contains(e) && !takenEntries.contains(e)
        }

        // Step 1.
        func rank(_ id: ToriID) -> (Double, Int, ToriID) {
            let s = history[id]!.states.last!
            return (FSRS.retrievability(elapsedDays: today - s.lastReviewDay, stability: s.stability, parameters), s.dueDay, id)
        }
        var reviews: [ToriID] = []
        let limit = max(0, quota == Int.max ? Int.max : quota - reviewedToday.count)
        for id in waiting.map({ (rank($0), $0) }).sorted(by: { $0.0 < $1.0 }).map(\.1) {
            if reviews.count >= limit { break }
            if passes(id) {
                takenEntries.insert(entryOf[id]!)
                reviews.append(id)
            }
        }

        // Step 2.
        var new: [ToriID] = []
        if !catchUp || extensions.extraNewBatches > 0 {
            // In catch-up only the extra batches are walked, so they start from zero.
            let alreadyIntroduced = catchUp ? 0 : introducedToday
            let newLimit = newWordsPerDay * (extensions.extraNewBatches + (catchUp ? 0 : 1))
            var newEntriesTaken = 0
            let candidates = active.flatMap { e in e.cards.map { (e, $0) } }
                .filter { !hasBefore($0.1.id, today) && !hasOn($0.1.id, today) }
                .sorted { ($0.0.createdAt, $0.1.direction, $0.1.id) < ($1.0.createdAt, $1.1.direction, $1.1.id) }
            for (e, c) in candidates where passes(c.id) {
                if entryIsNew[e.id]! {
                    guard alreadyIntroduced + newEntriesTaken < newLimit else { continue }
                    newEntriesTaken += 1
                }
                takenEntries.insert(e.id)
                new.append(c.id)
            }
        }
        let newEntryLeft = active.contains {
            entryIsNew[$0.id]! && !takenEntries.contains($0.id) && !entriesWithLogToday.contains($0.id)
        }

        let home: HomeState =
            entries.isEmpty ? .empty
            : active.isEmpty && entries.contains(where: { $0.cards.isEmpty }) ? .noneReviewable
            : !(reviews.isEmpty && new.isEmpty && reshow.isEmpty) ? .due
            : !answeredToday.isEmpty ? .allDone
            : .nothingDue
        return DailyQueue(reviews: reviews, new: new, reshow: reshow, waiting: waiting.count, catchUp: catchUp,
                          normalLoad: normalLoad, homeState: home, answeredToday: answeredToday.map(\.id),
                          introducedToday: introducedToday, canLearnMore: newEntryLeft && newWordsPerDay > 0)
    }
}

func ceilDiv(_ a: Int, _ b: Int) -> Int { a <= 0 ? -((-a) / b) : (a + b - 1) / b }
