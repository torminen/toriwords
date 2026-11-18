import Foundation
import ToriCore
import ToriStore

/// Background fills of pending Entries (doc 36 §6.4): dictionary first, MT fallback, three MT failures → `unavailable`.
/// Triggers (the app calls them): app foreground → `runPending`; translation data installed → `retryUnavailable`;
/// dictionary update → `updateDictionary`; "Try again" → `tryAgain`.
public actor EnrichmentOrchestrator {
    public struct RunSummary: Equatable, Sendable {
        public var filled = 0
        /// MT attempts that failed or returned nothing (each counted in `enrich_attempts`).
        public var failed = 0
        /// Left pending: no dictionary hit and MT not ready, or MT in backoff.
        public var deferred = 0
        public init() {}
    }

    private let store: ToriStore
    private var dictionary: (any DictionaryLookup)?
    private let translator: (any MachineTranslator)?
    private let now: @Sendable () -> Int64
    /// In-memory MT backoff so rapid foreground triggers do not burn the three attempts: 1 min, 2 min, 4 min…
    private var mtFailures: [ToriID: (count: Int, at: Int64)] = [:]
    private var isRunning = false
    private var rerun = false

    static let backoffBaseMs: Int64 = 60_000

    public init(store: ToriStore, dictionary: (any DictionaryLookup)?, translator: (any MachineTranslator)?,
                now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.store = store
        self.dictionary = dictionary
        self.translator = translator
        self.now = now
    }

    /// Variants for the Add / Entry screens: dictionary first, MT appended when ready and new (§6.2).
    public func suggestions(for text: String) async -> [Suggestion] {
        let headwords = lookup(text)
        var machine: String?
        if let translator, await translator.isReady() { machine = try? await translator.translate(text) }
        return Suggestions.build(headwords: headwords, dictVersion: dictionary?.version, machine: machine)
    }

    /// IPA of the first dictionary headword for the text (Add preview, §6.2 item 7).
    public func ipa(for text: String) -> String? {
        lookup(text).lazy.compactMap(\.ipa).first
    }

    /// "In this sentence: …" help on Add (P1, §6.2 item 5): only when on-device translation is ready; never stored.
    public func contextHelp(for sentence: String) async -> String? {
        guard let translator, await translator.isReady() else { return nil }
        return try? await translator.translate(sentence)
    }

    /// Fills every pending Entry once. Re-entrant calls while running are coalesced into one more pass.
    @discardableResult
    public func runPending() async throws -> RunSummary {
        if isRunning { rerun = true; return RunSummary() }
        isRunning = true
        defer { isRunning = false }
        var total = RunSummary()
        repeat {
            rerun = false
            let pass = try await pendingPass()
            total.filled += pass.filled
            total.failed += pass.failed
            total.deferred = pass.deferred
        } while rerun
        return total
    }

    /// A new dictionary build was installed: `unavailable` Entries get another chance (§6.4, §8.3).
    @discardableResult
    public func updateDictionary(_ dictionary: (any DictionaryLookup)?) async throws -> RunSummary {
        self.dictionary = dictionary
        return try await retryUnavailable()
    }

    /// A new source appeared (translation data installed): `unavailable` → `pending`, then fill.
    @discardableResult
    public func retryUnavailable() async throws -> RunSummary {
        for id in try store.read({ try $0.unavailableEnrichment() }) { try reset(id) }
        return try await runPending()
    }

    /// "Try again" on one Entry.
    @discardableResult
    public func tryAgain(_ id: ToriID) async throws -> RunSummary {
        try reset(id)
        return try await runPending()
    }

    private func reset(_ id: ToriID) throws {
        mtFailures[id] = nil
        try store.retryEnrichment(id)
    }

    private func pendingPass() async throws -> RunSummary {
        var summary = RunSummary()
        let ids = try store.read { try $0.pendingEnrichment() }
        guard !ids.isEmpty else { return summary }
        var mtReady: Bool?
        for id in ids {
            // No status check: a fill writes rank 0 only, so fields the user wrote (rank 1) stay as they are.
            guard let entry = try store.read({ try $0.entry(id) }) else { continue }
            let headwords = lookup(entry.text)
            if let first = Suggestions.build(headwords: headwords, dictVersion: dictionary?.version, machine: nil).first {
                try store.fillAutomaticSense(entry.id, first.sense)
                let ipa = headwords.first { $0.key == first.sense.dictHeadwordKey }?.ipa
                if entry.ipa == nil, let ipa { try store.setEntryIPA(entry.id, ipa, rank: .automatic) }
                summary.filled += 1
                continue
            }
            guard let translator else { summary.deferred += 1; continue }
            if mtReady == nil { mtReady = await translator.isReady() }
            guard mtReady == true, !inBackoff(entry.id) else { summary.deferred += 1; continue }
            let result: String?
            do {
                result = try await translator.translate(entry.text)?.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch is CancellationError {
                // MT went away mid-pass (the app left the foreground on iOS < 26): defer, never count a failure.
                mtReady = false
                summary.deferred += 1
                continue
            } catch {
                result = nil
            }
            if let result, !result.isEmpty {
                mtFailures[entry.id] = nil
                try store.fillAutomaticSense(entry.id, NewSense(translation: result, source: .mtApple))
                summary.filled += 1
            } else {
                let count = (mtFailures[entry.id]?.count ?? 0) + 1
                mtFailures[entry.id] = (count, now())
                try store.recordEnrichmentFailure(entry.id)
                summary.failed += 1
            }
        }
        return summary
    }

    private func inBackoff(_ id: ToriID) -> Bool {
        guard let f = mtFailures[id] else { return false }
        return now() < f.at + Self.backoffBaseMs << min(f.count - 1, 10)
    }

    /// A dictionary that cannot be read counts as "no hit": MT still gets its chance.
    private func lookup(_ text: String) -> [DictionaryHeadword] {
        (try? dictionary?.lookup(key: TextKey.matchKey(text))) ?? []
    }
}
