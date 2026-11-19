import Foundation
import Observation
import ToriCore
import ToriStore

/// What Home shows; computed in one read and re-emitted whenever `user.sqlite` changes.
struct HomeSnapshot: Equatable, Sendable {
    var state: HomeState
    var toReview: Int
    var new: Int
    var catchUp: Bool
    var waiting: Int
    /// Days from today to the next due day; nil when nothing is scheduled.
    var nextDueInDays: Int?
    var recent: [WordRow]
    /// Only for `noneReviewable`: "N words need a translation".
    var needsTranslation: Int

    static let recentLimit = 5

    static func read(_ r: StoreReader, now: Int64, utcOffsetMin: Int) throws -> HomeSnapshot {
        let queue = try r.dailyQueue(now: now, utcOffsetMin: utcOffsetMin)
        let today = DayModel.dayNumber(unixMs: now, utcOffsetMin: utcOffsetMin)
        let next = try r.widgetSnapshot(now: now, utcOffsetMin: utcOffsetMin).nextDueDay
        // ponytail: `words` reads every row to show five; add a LIMIT query if Home gets slow with large vocabularies.
        let recent = queue.homeState == .empty ? [] : Array(try r.words(WordsQuery(sort: .newest)).prefix(recentLimit))
        let needs = queue.homeState == .noneReviewable ? try r.words(WordsQuery(filter: .needsTranslation)).count : 0
        return HomeSnapshot(state: queue.homeState, toReview: queue.toReviewCount, new: queue.newCount, catchUp: queue.catchUp,
                            waiting: queue.waiting, nextDueInDays: next.map { $0 - today }, recent: recent, needsTranslation: needs)
    }
}

@MainActor @Observable
final class HomeModel {
    private(set) var snapshot: HomeSnapshot?
    private let store: ToriStore

    init(store: ToriStore) { self.store = store }

    /// Live until the calling task is cancelled; `now` is read on every change so the day rolls over on the next write
    /// or when the view restarts the task (scene becomes active).
    func observe() async {
        let observation = store.observe { r in try HomeSnapshot.read(r, now: Now.ms, utcOffsetMin: Now.utcOffsetMin) }
        do {
            for try await value in observation { snapshot = value }
        } catch {
            // The observation only fails if the database is unusable; Home keeps its last value.
        }
    }
}
