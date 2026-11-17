import Foundation
import Observation
import ToriCore
import ToriEnrichment
import ToriStore

/// What one card shows; read fresh from the store each time a card appears (an edit shows immediately, §5.6).
struct CardContent: Equatable {
    struct Sentence: Equatable {
        var text: String
        var highlight: Capture.Highlight?
        var source: String?
    }

    struct Meaning: Equatable {
        var translation: String?
        var definition: String?
    }

    var card: ReviewSession.Card
    var direction: CardDirection
    var word: String
    var ipa: String?
    var partOfSpeech: String?
    var meanings: [Meaning]
    /// Sentence on the front: any sentence for recognition; only highlighted ones for recall and cloze (§7.8).
    var frontSentence: Sentence?
    /// The back repeats the front's sentence, or shows the rotated one when the front had none.
    var backSentence: Sentence?

    var translations: [String] { meanings.compactMap(\.translation).filter { !$0.isEmpty } }
}

@MainActor @Observable
final class ReviewModel {
    enum Screen: Equatable {
        case loading
        case card(CardContent)
        case allDone(ReviewSession.Summary, nextDueInDays: Int?, canLearnMore: Bool)
        case nothingDue(nextDueInDays: Int?, canLearnMore: Bool)
        case nothingAdded
    }

    private(set) var screen: Screen = .loading
    private(set) var isFlipped = false
    private(set) var position = 0
    private(set) var total = 0
    private(set) var canUndo = false
    /// Set once when the session reaches the summary for the first time ever (reminder offer, §5.6).
    var showReminderOffer = false
    var errorMessage: String?

    private var session = ReviewSession(cards: [], newEntries: [])
    private var shownAt: Int64 = 0
    private var extraNewBatches = 0
    private let store: ToriStore
    private let env: AppEnvironment

    init(store: ToriStore, env: AppEnvironment) {
        self.store = store
        self.env = env
    }

    // MARK: Lifecycle

    func start() {
        env.activeReview = self
        do {
            let (queue, newEntries) = try store.read { r in
                (try r.dailyQueue(now: Now.ms, utcOffsetMin: Now.utcOffsetMin), try Self.newEntries(r))
            }
            if queue.sessionOrder.isEmpty {
                if queue.homeState == .empty {
                    screen = .nothingAdded
                } else {
                    let next = try nextDueInDays()
                    screen = .nothingDue(nextDueInDays: next, canLearnMore: queue.canLearnMore)
                }
                return
            }
            session = ReviewSession(cards: try cards(queue.sessionOrder), newEntries: newEntries)
            showCurrent()
        } catch {
            fail(error)
        }
    }

    /// ✕ / Back / Done: commits the undoable answer; given answers are kept.
    func close() {
        commitPending()
        env.speech.stop()
        if env.activeReview === self { env.activeReview = nil }
    }

    /// Session end or app background (§7.8).
    func commitPending() {
        if let answer = session.flush() { commit(answer) }
        canUndo = false
    }

    // MARK: Card actions

    func flip() {
        guard case .card(let c) = screen, !isFlipped else { return }
        isFlipped = true
        if env.settings.autoPlayOnReveal { env.speak(c.word, .autoPlay) }
    }

    func grade(_ rating: Rating) {
        guard case .card = screen, isFlipped else { return }
        if let previous = session.answer(rating, at: Now.ms, utcOffsetMin: Now.utcOffsetMin, shownAt: shownAt) {
            commit(previous)
        }
        showCurrent()
    }

    func undo() {
        session.undo()
        showCurrent()
    }

    /// Back from ••• Edit: re-read the same card.
    func reloadCurrent() {
        guard case .card = screen else { return }
        let flipped = isFlipped
        showCurrent(resetTimer: false)
        isFlipped = flipped
    }

    func setStatus(_ status: EntryStatus) {
        guard case .card(let c) = screen else { return }
        perform { try store.setStatus([c.card.entry], status) }
        session.remove(entry: c.card.entry)
        showCurrent()
    }

    /// Delete with the shared Undo toast (§5.7). Undo keeps the word, but its cards stay out of this session.
    func delete() {
        guard case .card(let c) = screen else { return }
        env.deletion.schedule([c.card.entry], word: c.word)
        session.remove(entry: c.card.entry)
        showCurrent()
    }

    /// "Learn more new words": one more batch for this session only (§7.7).
    func learnMore() {
        commitPending()
        extraNewBatches += 1
        do {
            let (queue, newEntries) = try store.read { r in
                (try r.dailyQueue(now: Now.ms, utcOffsetMin: Now.utcOffsetMin,
                                  extensions: QueueExtensions(extraNewBatches: extraNewBatches)), try Self.newEntries(r))
            }
            let more = try cards(queue.new)
            if session.isFinished && session.summary.reviewed == 0 {
                session = ReviewSession(cards: more, newEntries: newEntries)
            } else {
                session.append(more)
            }
            showCurrent()
        } catch {
            fail(error)
        }
    }


    // MARK: Internals

    private func showCurrent(resetTimer: Bool = true) {
        env.speech.stop()
        isFlipped = false
        canUndo = session.canUndo
        while let card = session.current {
            do {
                if let content = try load(card) {
                    position = session.position
                    total = session.total
                    if resetTimer { shownAt = Now.ms }
                    screen = .card(content)
                    return
                }
                // Entry deleted or excluded meanwhile: its cards leave the list.
                session.remove(entry: card.entry)
            } catch {
                fail(error)
                return
            }
        }
        finish()
    }

    private func finish() {
        commitPending()
        do {
            let queue = try store.read { try $0.dailyQueue(now: Now.ms, utcOffsetMin: Now.utcOffsetMin) }
            let next = try nextDueInDays()
            screen = .allDone(session.summary, nextDueInDays: next, canLearnMore: queue.canLearnMore)
            if !env.settings.reminderOfferShown && session.summary.reviewed > 0 {
                env.settings.reminderOfferShown = true
                showReminderOffer = true
            }
        } catch {
            fail(error)
        }
    }

    private func commit(_ a: ReviewSession.Answer) {
        perform {
            try store.commitAnswer(card: a.card.id, rating: a.rating, reviewedAt: a.reviewedAt, utcOffsetMin: a.utcOffsetMin,
                                   answerMs: a.answerMs)
        }
        env.didCommitAnswer()
    }

    private func perform(_ write: () throws -> Void) {
        do { try write() } catch { fail(error) }
    }

    private func fail(_ error: any Error) {
        errorMessage = String(describing: error)
    }

    private func cards(_ ids: [ToriID]) throws -> [ReviewSession.Card] {
        try store.read { r in
            try ids.compactMap { id in try r.cardEntry(id).map { ReviewSession.Card(id: id, entry: $0) } }
        }
    }

    private func nextDueInDays() throws -> Int? {
        try store.read { try $0.widgetSnapshot(now: Now.ms, utcOffsetMin: Now.utcOffsetMin) }.nextDueDay.map { $0 - Now.today }
    }

    /// Entries with no rated log yet: answering one of their cards introduces a new word (summary, §7.8).
    private nonisolated static func newEntries(_ r: StoreReader) throws -> Set<ToriID> {
        let (entries, logs) = try r.queueInput()
        let answered = Set(logs.filter { $0.rating != nil }.map(\.cardID))
        return Set(entries.filter { e in e.cards.allSatisfy { !answered.contains($0.id) } }.map(\.id))
    }

    private func load(_ card: ReviewSession.Card) throws -> CardContent? {
        guard let entry = try store.read({ try $0.entry(card.entry) }), entry.status == .active,
              let detail = entry.cards.first(where: { $0.id == card.id }) else { return nil }
        let rotation = entry.contexts.map {
            SentenceRotation.Context(id: $0.id, capturedAt: $0.capturedAt, hasSentence: $0.sentence?.isEmpty == false,
                                     hasHighlight: $0.highlight != nil)
        }
        func sentence(_ id: ToriID?) -> CardContent.Sentence? {
            guard let c = entry.contexts.first(where: { $0.id == id }), let text = c.sentence else { return nil }
            return .init(text: text, highlight: c.highlight, source: c.sourceTitle ?? c.sourceURL.flatMap { URL(string: $0)?.host() })
        }
        let front = SentenceRotation.pick(rotation, reps: detail.reps, needsHighlight: detail.direction != .recognition)
        let back = front ?? SentenceRotation.pick(rotation, reps: detail.reps, needsHighlight: false)
        return CardContent(
            card: card, direction: detail.direction, word: entry.text, ipa: entry.ipa,
            partOfSpeech: entry.senses.compactMap(\.partOfSpeech).first,
            meanings: entry.senses.map { .init(translation: $0.translation, definition: $0.definition) },
            frontSentence: sentence(front), backSentence: sentence(back))
    }
}
