import Foundation
import Testing
@testable import ToriCore

/// Day 20402 = 2025-11-10 (Monday). Offset +180 (Moscow).
private func snapshot(_ days: [(Int, Int, Int)]) throws -> WidgetSnapshot {
    let json = """
    {"format":1,"generatedAt":0,"utcOffsetMin":180,"nextDueDay":null,"homeState":"due",
     "days":[\(days.map { "{\"day\":\($0.0),\"dueReviews\":\($0.1),\"newAvailable\":\($0.2)}" }.joined(separator: ","))]}
    """
    return try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
}

/// Unix ms of a local Moscow time on 2025-11-<day>.
private func moscow(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Int64 {
    (Int64(20402 + day - 10) * 86_400 + Int64(hour * 3600 + minute * 60) - 180 * 60) * 1000
}

@Test func remindersOnlyOnDaysWithSomethingToReview() throws {
    let s = try snapshot([(20402, 3, 2), (20403, 0, 0), (20404, 0, 5), (20405, 7, 0)])
    let r = ReminderPlan.requests(snapshot: s, hour: 19, minute: 30, now: moscow(10, 9), utcOffsetMin: 180)
    #expect(r.map(\.identifier) == ["reminder-20402", "reminder-20404", "reminder-20405"])
    #expect(r.map(\.count) == [5, 5, 7])
    #expect(r.map { [$0.year, $0.month, $0.day, $0.hour, $0.minute] } == [[2025, 11, 10, 19, 30], [2025, 11, 12, 19, 30],
                                                                         [2025, 11, 13, 19, 30]])
}

@Test func todaySkippedOnceTheTimeHasPassed() throws {
    let s = try snapshot([(20402, 3, 0), (20403, 1, 0)])
    #expect(ReminderPlan.requests(snapshot: s, hour: 19, minute: 0, now: moscow(10, 19), utcOffsetMin: 180)
        .map(\.reviewDay) == [20403])
    #expect(ReminderPlan.requests(snapshot: s, hour: 19, minute: 0, now: moscow(10, 18, 59), utcOffsetMin: 180)
        .map(\.reviewDay) == [20402, 20403])
}

@Test func reminderBefore4AMFiresOnTheNextCalendarDate() throws {
    let s = try snapshot([(20402, 3, 0)])
    // 01:30 belongs to review day 20402 when it falls on Nov 11.
    let r = ReminderPlan.requests(snapshot: s, hour: 1, minute: 30, now: moscow(10, 23), utcOffsetMin: 180)
    #expect(r.map { [$0.reviewDay, $0.month, $0.day, $0.hour] } == [[20402, 11, 11, 1]])
    #expect(DayModel.dayNumber(unixMs: moscow(11, 1, 30), utcOffsetMin: 180) == 20402)
}

@Test func staleSnapshotDaysBeforeTodayAreDropped() throws {
    let s = try snapshot([(20400, 9, 0), (20401, 9, 0), (20402, 2, 0)])
    #expect(ReminderPlan.requests(snapshot: s, hour: 19, minute: 0, now: moscow(10, 8), utcOffsetMin: 180)
        .map(\.reviewDay) == [20402])
}

@Test func civilDates() {
    #expect(ReminderPlan.civil(fromDays: 0) == (1970, 1, 1))
    #expect(ReminderPlan.civil(fromDays: 20402) == (2025, 11, 10))
    #expect(ReminderPlan.civil(fromDays: 11016) == (2000, 2, 29))
    #expect(ReminderPlan.civil(fromDays: -1) == (1969, 12, 31))
}
