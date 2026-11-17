/// `widget-snapshot.json`, doc 36 §10.1.
public struct WidgetSnapshot: Hashable, Codable, Sendable {
    public struct Day: Hashable, Codable, Sendable {
        public var day: Int
        public var dueReviews: Int
        public var newAvailable: Int
    }

    public var format: Int
    public var generatedAt: Int64
    public var utcOffsetMin: Int
    public var days: [Day]
    public var nextDueDay: Int?
    public var homeState: HomeState

    /// Today and the next 6 days; day T+k (k ≥ 1) applies §7.7 assuming no further answers.
    public static func compute(entries: [QueueEntry], logs: [ReviewLogInput], now: Int64, utcOffsetMin: Int,
                               newWordsPerDay: Int, parameters: FSRSParameters = .default) -> WidgetSnapshot {
        let today = DayModel.dayNumber(unixMs: now, utcOffsetMin: utcOffsetMin)
        var home = HomeState.empty
        let days = (0..<7).map { k in
            let q = DailyQueue.build(entries: entries, logs: logs, today: today + k, newWordsPerDay: newWordsPerDay,
                                     parameters: parameters)
            if k == 0 { home = q.homeState }
            return Day(day: today + k, dueReviews: q.toReviewCount, newAvailable: q.newCount)
        }
        return WidgetSnapshot(format: 1, generatedAt: now, utcOffsetMin: utcOffsetMin, days: days,
                              nextDueDay: days.first { $0.dueReviews + $0.newAvailable > 0 }?.day, homeState: home)
    }
}
