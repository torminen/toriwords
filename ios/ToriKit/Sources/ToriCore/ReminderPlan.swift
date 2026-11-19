/// Daily reminder requests from the widget snapshot.
public enum ReminderPlan {
    /// One `UNCalendarNotificationTrigger` request (`repeats: false`) at a local calendar date and time.
    public struct Request: Hashable, Sendable {
        /// `reminder-<review day>`.
        public var identifier: String
        public var reviewDay: Int
        public var year: Int
        public var month: Int
        public var day: Int
        public var hour: Int
        public var minute: Int
        /// "N to review": `dueReviews + newAvailable` of that review day.
        public var count: Int
    }

    /// Up to 7 requests, one per snapshot day with something to review, at `hour:minute` local time.
    /// A time before 04:00 belongs to the previous review day, so it fires on the next calendar date.
    /// Requests whose fire instant is not after `now` are skipped; so are snapshot days before today.
    /// A day with only new words fires: the trigger is reviews + new words > 0.
    public static func requests(snapshot: WidgetSnapshot, hour: Int, minute: Int, now: Int64, utcOffsetMin: Int) -> [Request] {
        let today = DayModel.dayNumber(unixMs: now, utcOffsetMin: utcOffsetMin)
        let shift = hour < 4 ? 1 : 0  // the review day starts at 04:00
        return snapshot.days.compactMap { d in
            let count = d.dueReviews + d.newAvailable
            guard d.day >= today, count > 0 else { return nil }
            let civilDay = d.day + shift
            let fireMs = (Int64(civilDay) * 86_400 + Int64(hour * 3600 + minute * 60) - Int64(utcOffsetMin) * 60) * 1000
            guard fireMs > now else { return nil }
            let (y, m, dd) = civil(fromDays: civilDay)
            return Request(identifier: "reminder-\(d.day)", reviewDay: d.day, year: y, month: m, day: dd, hour: hour,
                           minute: minute, count: count)
        }
    }

    /// Days since 1970-01-01 → proleptic Gregorian (year, month, day) (H. Hinnant's `civil_from_days`).
    static func civil(fromDays z: Int) -> (Int, Int, Int) {
        let z = z + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }
}
