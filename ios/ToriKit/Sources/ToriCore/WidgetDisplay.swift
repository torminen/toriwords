/// What the widget shows for a snapshot at a render instant (doc 36 §10.2, UI doc §3.12, UQ-4 closed).
public enum WidgetDisplay: Hashable, Sendable {
    /// "12 to review · 5 new".
    case due(reviews: Int, new: Int)
    /// "Next review: tomorrow" (or a date; never a time). `day` is a §7.2 day number.
    case next(day: Int, isTomorrow: Bool)
    /// Missing, stale (> 7 days), nothing scheduled, or past the snapshot's days: "Open ToriWords".
    case openApp

    public static let staleAfterMs: Int64 = 7 * 86_400_000

    /// `utcOffsetMin` is the device's offset at the render instant (the widget recomputes "today" itself).
    public init(snapshot: WidgetSnapshot?, now: Int64, utcOffsetMin: Int) {
        guard let s = snapshot, now - s.generatedAt <= Self.staleAfterMs,
              s.homeState != .empty, s.homeState != .noneReviewable else { self = .openApp; return }
        let today = DayModel.dayNumber(unixMs: now, utcOffsetMin: utcOffsetMin)
        guard let i = s.days.firstIndex(where: { $0.day == today }) else { self = .openApp; return }
        let d = s.days[i]
        if d.dueReviews + d.newAvailable > 0 { self = .due(reviews: d.dueReviews, new: d.newAvailable); return }
        guard let next = s.days[(i + 1)...].first(where: { $0.dueReviews + $0.newAvailable > 0 }) else {
            self = .openApp
            return
        }
        self = .next(day: next.day, isTomorrow: next.day == today + 1)
    }

    /// Timeline instants: each 04:00 day boundary (in the snapshot's offset) after `now`, for the next `count` days.
    public static func dayBoundaries(after now: Int64, utcOffsetMin: Int, count: Int = 7) -> [Int64] {
        let today = DayModel.dayNumber(unixMs: now, utcOffsetMin: utcOffsetMin)
        return (1...count).map { k in (Int64(today + k) * 86_400 + 4 * 3_600 - Int64(utcOffsetMin) * 60) * 1_000 }
    }
}
