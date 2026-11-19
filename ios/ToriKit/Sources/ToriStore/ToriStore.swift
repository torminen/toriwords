import Foundation
import GRDB
import ToriCore

/// Owner of `user.sqlite`. All writes go through `write`, which stamps clocks, fills the outbox and runs
/// the post-write maintenance (canonical IDs, duplicate merge, Card creation, replay) in the same transaction.
public final class ToriStore: Sendable {
    let db: DatabasePool
    let clock: @Sendable () -> Int64

    /// `now` returns Unix ms; injectable for tests.
    public init(path: String, now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        // encoding defaults to UTF-8 (set before any table exists); WAL is the pool's mode; GRDB enables foreign_keys.
        db = try DatabasePool(path: path, configuration: config)
        clock = now
        try Schema.migrator.migrate(db)
    }

    /// One write transaction with clock stamping and post-write maintenance.
    @discardableResult
    func write<T>(_ body: (Tx) throws -> T) throws -> T {
        try db.write { db in
            let tx = try Tx(db: db, now: clock())
            let result = try body(tx)
            try tx.finish()
            return result
        }
    }

    /// Read-only access for queries; see `StoreReader`.
    public func read<T>(_ body: (StoreReader) throws -> T) throws -> T {
        try db.read { try body(StoreReader(db: $0)) }
    }

    /// Observation of any query: emits on change, duplicates removed.
    public func observe<T: Equatable & Sendable>(_ query: @escaping @Sendable (StoreReader) throws -> T)
        -> AsyncValueObservation<T> {
        ValueObservation.tracking { try query(StoreReader(db: $0)) }.removeDuplicates().values(in: db)
    }

    /// `PRAGMA wal_checkpoint(TRUNCATE)` on background.
    public func checkpoint() throws {
        try db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)") }
    }
}

/// Read-only query surface (UI queries live in extensions).
public struct StoreReader {
    let db: Database
}
