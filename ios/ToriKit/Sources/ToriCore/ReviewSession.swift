/// In-memory review session: the card list, the one uncommitted answer (undo), Forgot re-shows and the
/// session summary. Pure: the caller persists each `Answer` it gets back and passes the clock in.
public struct ReviewSession: Sendable {
    public struct Card: Hashable, Sendable {
        public var id: ToriID
        public var entry: ToriID
        public init(id: ToriID, entry: ToriID) {
            self.id = id
            self.entry = entry
        }
    }

    public struct Answer: Hashable, Sendable {
        public var card: Card
        public var rating: Rating
        public var reviewedAt: Int64
        public var utcOffsetMin: Int
        /// Time from the card being shown to the answer, capped at 10 min.
        public var answerMs: Int
    }

    public struct Summary: Hashable, Sendable {
        /// Distinct Cards answered.
        public var reviewed: Int
        /// Distinct Cards whose first answer in the session was Remembered.
        public var remembered: Int
        /// Entries introduced in this session (no rated log before it).
        public var newWords: Int
    }

    /// A Forgot card comes back this many cards later (or last when fewer remain).
    public static let reshowGap = 3
    public static let maxAnswerMs = 600_000

    public private(set) var remaining: [Card]
    /// Held for ↶; committed by the next answer, `flush()`, or the session end.
    public private(set) var pending: Answer?
    private var beforePending: [Card] = []
    private var committed: [Answer] = []
    private let newEntries: Set<ToriID>
    private let reshowsForgot: Bool

    /// `newEntries`: Entries with no rated log before the session started.
    /// `reshowsForgot: false` (practice) shows every card once: Forgot does not bring it back.
    public init(cards: [Card], newEntries: Set<ToriID>, reshowsForgot: Bool = true) {
        remaining = cards
        self.newEntries = newEntries
        self.reshowsForgot = reshowsForgot
    }

    public var current: Card? { remaining.first }
    public var canUndo: Bool { pending != nil }
    public var isFinished: Bool { remaining.isEmpty }
    /// "2 / 17": 1-based position of the current card; the total grows with re-shows.
    public var position: Int { answeredCount + 1 }
    public var total: Int { answeredCount + remaining.count }
    private var answeredCount: Int { committed.count + (pending == nil ? 0 : 1) }

    /// Answers the current card. Returns the previously pending answer, which the caller must commit now.
    public mutating func answer(_ rating: Rating, at now: Int64, utcOffsetMin: Int, shownAt: Int64) -> Answer? {
        guard let card = remaining.first else { return nil }
        let toCommit = flush()
        beforePending = remaining
        remaining.removeFirst()
        if rating == .forgot && reshowsForgot {
            remaining.insert(card, at: min(Self.reshowGap, remaining.count))
        }
        pending = Answer(card: card, rating: rating, reviewedAt: now, utcOffsetMin: utcOffsetMin,
                         answerMs: Int(min(max(now - shownAt, 0), Int64(Self.maxAnswerMs))))
        return toCommit
    }

    /// ↶: drops the uncommitted answer and brings its card back in front.
    public mutating func undo() {
        guard pending != nil else { return }
        pending = nil
        remaining = beforePending
    }

    /// Session end or app background: returns the pending answer to commit; nothing is undoable afterwards.
    public mutating func flush() -> Answer? {
        guard let p = pending else { return nil }
        committed.append(p)
        pending = nil
        return p
    }

    /// Entry deleted or excluded mid-session: its cards leave the list.
    public mutating func remove(entry: ToriID) {
        remaining.removeAll { $0.entry == entry }
        beforePending.removeAll { $0.entry == entry }
    }

    /// "Learn more new words": appends Cards not already waiting.
    public mutating func append(_ cards: [Card]) {
        let waiting = Set(remaining.map(\.id))
        remaining += cards.filter { !waiting.contains($0.id) }
    }

    /// Counts committed answers only (call `flush()` first at the end).
    public var summary: Summary {
        var first: [ToriID: Rating] = [:]
        for a in committed where first[a.card.id] == nil { first[a.card.id] = a.rating }
        return Summary(reviewed: first.count, remembered: first.values.filter { $0 == .remembered }.count,
                       newWords: Set(committed.map(\.card.entry)).intersection(newEntries).count)
    }
}

/// Which sentence a card shows: index `reps mod count` over the eligible Contexts ordered by
/// (`captured_at`, `id`). Recall and cloze use only Contexts with a highlight.
public enum SentenceRotation {
    public struct Context: Hashable, Sendable {
        public var id: ToriID
        public var capturedAt: Int64
        public var hasSentence: Bool
        public var hasHighlight: Bool
        public init(id: ToriID, capturedAt: Int64, hasSentence: Bool, hasHighlight: Bool) {
            self.id = id
            self.capturedAt = capturedAt
            self.hasSentence = hasSentence
            self.hasHighlight = hasHighlight
        }
    }

    public static func pick(_ contexts: [Context], reps: Int, needsHighlight: Bool) -> ToriID? {
        let eligible = contexts
            .filter { $0.hasSentence && (!needsHighlight || $0.hasHighlight) }
            .sorted { $0.capturedAt != $1.capturedAt ? $0.capturedAt < $1.capturedAt : $0.id < $1.id }
        guard !eligible.isEmpty else { return nil }
        return eligible[max(reps, 0) % eligible.count].id
    }
}
