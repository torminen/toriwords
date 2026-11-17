import GRDB
import ToriCore

// API-first commit: bodies follow in the next commit.
final class Tx {
    let db: Database
    init(db: Database, now: Int64) throws { self.db = db }
    func finish() throws {}
}

enum Outbox {
    static func batch(_ db: Database, maxRecords: Int) throws -> PushBatch { fatalError("step 6") }
    static func acknowledge(_ db: Database, rows: [OutboxRow], acked: Set<ToriID>) throws { fatalError("step 6") }
    static func markAll(_ db: Database) throws { fatalError("step 6") }
    static func recoverClockAhead(_ tx: Tx, lastServerTime: Int64) throws -> Bool { fatalError("step 6") }
}

enum Apply {
    static func page(_ tx: Tx, _ records: [SyncRecord]) throws -> PulledPageResult { fatalError("step 6") }
}
