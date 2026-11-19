/// Progress / stats. Pure functions over live data (deleted Entries and their logs excluded by the caller).
public enum ProgressStats {
    /// Progress → Today.
    public struct Today: Hashable, Sendable {
        public var cardsReviewed: Int
        public var toReview: Int
        public var new: Int
        public var newWordsIntroduced: Int

        public init(cardsReviewed: Int, toReview: Int, new: Int, newWordsIntroduced: Int) {
            self.cardsReviewed = cardsReviewed
            self.toReview = toReview
            self.new = new
            self.newWordsIntroduced = newWordsIntroduced
        }
    }

    public static func today(_ queue: DailyQueue) -> Today {
        Today(cardsReviewed: queue.cardsAnsweredToday, toReview: queue.toReviewCount, new: queue.newCount,
              newWordsIntroduced: queue.introducedToday)
    }

    /// Entry status as Progress counts it.
    public enum EntryStatus: Sendable {
        case active(CardStage)
        case alreadyKnown
        case paused
    }

    public struct Vocabulary: Hashable, Sendable {
        public var new: Int, learning: Int, knownWell: Int, alreadyKnown: Int, paused: Int

        public init(new: Int = 0, learning: Int = 0, knownWell: Int = 0, alreadyKnown: Int = 0, paused: Int = 0) {
            (self.new, self.learning, self.knownWell, self.alreadyKnown, self.paused) = (new, learning, knownWell, alreadyKnown, paused)
        }
    }

    /// Active Entries by Entry-level stage (`entryStage`), excluded ones by reason.
    public static func vocabulary(_ entries: [EntryStatus]) -> Vocabulary {
        var v = Vocabulary()
        for e in entries {
            switch e {
            case .active(.new): v.new += 1
            case .active(.learning): v.learning += 1
            case .active(.knownWell): v.knownWell += 1
            case .alreadyKnown: v.alreadyKnown += 1
            case .paused: v.paused += 1
            }
        }
        return v
    }

    /// Rated logs per review day for T−29…T (oldest first); each log counts on its own review day.
    public static func activity(logs: [ReviewLogInput], today: Int) -> [Int] {
        var counts = Array(repeating: 0, count: 30)
        for l in logs where l.rating != nil {
            let i = l.reviewDay - (today - 29)
            if counts.indices.contains(i) { counts[i] += 1 }
        }
        return counts
    }

    /// Entries created per week for the last 8 weeks (7-day blocks of review days ending today, T−55…T; oldest first).
    /// `createdAt` uses the current offset.
    public static func capturedPerWeek(createdAt: [Int64], today: Int, utcOffsetMin: Int) -> [Int] {
        var weeks = Array(repeating: 0, count: 8)
        for t in createdAt {
            let back = today - DayModel.dayNumber(unixMs: t, utcOffsetMin: utcOffsetMin)
            if (0..<56).contains(back) { weeks[7 - back / 7] += 1 }
        }
        return weeks
    }

    public struct SourceUsage: Hashable, Sendable {
        public var id: ToriID
        public var title: String?
        public var url: String?
        public var isSuggested: Bool
        /// Live Entries with a Context from this Source.
        public var entryCount: Int

        public init(id: ToriID, title: String?, url: String?, isSuggested: Bool, entryCount: Int) {
            self.id = id
            self.title = title
            self.url = url
            self.isSuggested = isSuggested
            self.entryCount = entryCount
        }

        /// The title; without one, the URL host without a leading `www.`.
        public var label: String {
            if let title, !title.isEmpty { return title }
            return url.map(Self.host) ?? ""
        }

        static func host(_ url: String) -> String {
            var s = Substring(url)
            if let r = s.range(of: "://") { s = s[r.upperBound...] }
            s = s.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
            if let at = s.lastIndex(of: "@") { s = s[s.index(after: at)...] }
            if !s.hasPrefix("["), let colon = s.lastIndex(of: ":") { s = s[..<colon] }
            return String(s.hasPrefix("www.") ? s.dropFirst(4) : s)
        }
    }

    /// Top 5 Sources by Entry count; ties by label, then ID. Suggested Sources and Sources without Entries are not counted.
    public static func topSources(_ sources: [SourceUsage]) -> [SourceUsage] {
        Array(sources.filter { !$0.isSuggested && $0.entryCount > 0 }
            .sorted { ($1.entryCount, $0.label.utf8Ordered, $0.id) < ($0.entryCount, $1.label.utf8Ordered, $1.id) }
            .prefix(5))
    }
}

extension String {
    /// UTF-8 byte order (BINARY collation), independent of Swift's String comparison.
    var utf8Ordered: UTF8Key { UTF8Key(bytes: Array(utf8)) }
}

struct UTF8Key: Comparable {
    var bytes: [UInt8]
    static func < (a: Self, b: Self) -> Bool { a.bytes.lexicographicallyPrecedes(b.bytes) }
}
