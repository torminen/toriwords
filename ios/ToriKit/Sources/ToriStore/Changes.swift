import GRDB

extension ToriStore {
    /// One event per committed transaction that touched vocabulary or scheduling data (not sync bookkeeping), for the
    /// debounced App Group refresh (§5.4, §10.1). Ends when the consumer stops iterating.
    public func vocabularyChanges() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observation = DatabaseRegionObservation(tracking: ["entry", "sense", "card", "review_log", "tag", "entry_tag",
                                                                   "settings"].map(Table.init))
            let cancellable = observation.start(in: db, onError: { _ in continuation.finish() },
                                                onChange: { _ in continuation.yield() })
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}

extension StoreReader {
    /// Outbox rows; the app schedules a debounced sync when this grows (§11.5 "~5 s after a local change").
    public func pendingChangeCount() throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pending_changes") ?? 0
    }
}
