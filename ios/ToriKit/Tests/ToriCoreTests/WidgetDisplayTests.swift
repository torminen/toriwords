import Testing
@testable import ToriCore

private let day0 = 20402
/// 12:00 local on `day` at offset +180.
private func noon(_ day: Int, offset: Int = 180) -> Int64 { (Int64(day) * 86_400 + 12 * 3_600 - Int64(offset) * 60) * 1_000 }

private func snapshot(_ counts: [(Int, Int)], home: HomeState = .due, generatedAt: Int64 = noon(day0)) -> WidgetSnapshot {
    let days = counts.enumerated().map { WidgetSnapshot.Day(day: day0 + $0.offset, dueReviews: $0.element.0, newAvailable: $0.element.1) }
    return WidgetSnapshot(format: 1, generatedAt: generatedAt, utcOffsetMin: 180, days: days,
                          nextDueDay: days.first { $0.dueReviews + $0.newAvailable > 0 }?.day, homeState: home)
}

@Test func dueTodayShowsBothCounts() {
    #expect(WidgetDisplay(snapshot: snapshot([(12, 5), (3, 0)]), now: noon(day0), utcOffsetMin: 180) == .due(reviews: 12, new: 5))
}

@Test func laterDayIsRecomputedFromTheRenderInstant() {
    let s = snapshot([(0, 0), (0, 0), (4, 0)], home: .allDone)
    #expect(WidgetDisplay(snapshot: s, now: noon(day0), utcOffsetMin: 180) == .next(day: day0 + 2, isTomorrow: false))
    #expect(WidgetDisplay(snapshot: s, now: noon(day0 + 1), utcOffsetMin: 180) == .next(day: day0 + 2, isTomorrow: true))
    #expect(WidgetDisplay(snapshot: s, now: noon(day0 + 2), utcOffsetMin: 180) == .due(reviews: 4, new: 0))
    // 03:59 local still belongs to the previous review day.
    let beforeBoundary = (Int64(day0 + 2) * 86_400 + 4 * 3_600 - 180 * 60) * 1_000 - 60_000
    #expect(WidgetDisplay(snapshot: s, now: beforeBoundary, utcOffsetMin: 180) == .next(day: day0 + 2, isTomorrow: true))
}

@Test func missingStaleEmptyOrNothingScheduledOpensTheApp() {
    #expect(WidgetDisplay(snapshot: nil, now: noon(day0), utcOffsetMin: 180) == .openApp)
    #expect(WidgetDisplay(snapshot: snapshot([(1, 0)]), now: noon(day0) + WidgetDisplay.staleAfterMs + 1, utcOffsetMin: 180) == .openApp)
    #expect(WidgetDisplay(snapshot: snapshot([(0, 0)], home: .empty), now: noon(day0), utcOffsetMin: 180) == .openApp)
    #expect(WidgetDisplay(snapshot: snapshot([(0, 0)], home: .noneReviewable), now: noon(day0), utcOffsetMin: 180) == .openApp)
    #expect(WidgetDisplay(snapshot: snapshot(Array(repeating: (0, 0), count: 7), home: .nothingDue), now: noon(day0), utcOffsetMin: 180) == .openApp)
    #expect(WidgetDisplay(snapshot: snapshot([(1, 0)]), now: noon(day0 + 1), utcOffsetMin: 180) == .openApp)  // past the days
}

@Test func timelineEntriesAtEachFourAMBoundary() {
    let b = WidgetDisplay.dayBoundaries(after: noon(day0), utcOffsetMin: 180)
    #expect(b.count == 7)
    #expect(b.enumerated().allSatisfy { DayModel.dayNumber(unixMs: $0.element, utcOffsetMin: 180) == day0 + 1 + $0.offset })
    #expect(b.allSatisfy { DayModel.dayNumber(unixMs: $0 - 1, utcOffsetMin: 180) == DayModel.dayNumber(unixMs: $0, utcOffsetMin: 180) - 1 })
}
