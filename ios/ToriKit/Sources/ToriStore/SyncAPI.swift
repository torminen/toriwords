import Foundation
import GRDB
import ToriCore

/// `sync_state` keys (doc 36 §4.2).
public enum SyncStateKey: String, CaseIterable, Sendable {
    case cursor, hlc, accountId, lastSyncedAccountId, pendingAccountChoice, adoptedAccountId, lastServerTime, lastSyncAt,
         signInBaseline, lastProvider
}

/// One outbox row (doc 36 §11.4). `field == "*"` = the whole record; `_deleted` / `_mergedInto` = envelope changes.
public struct OutboxRow: Hashable, Sendable {
    public var recordID: ToriID
    public var type: String
    public var field: String
    public var clock: String
}

/// Envelopes built from the outbox, plus the rows they cover (pass them back to `acknowledge`).
public struct PushBatch: Sendable {
    public var records: [SyncRecord]
    public var rows: [OutboxRow]
}

public struct PulledPageResult: Sendable, Equatable {
    /// Records of a type this version does not know (§11.8 backfill).
    public var skippedUnknownTypes: Set<String>
}

/// The API ToriSync (step 7) calls. Every method is one transaction.
extension ToriStore {
    public func syncState(_ key: SyncStateKey) throws -> String? {
        try db.read { try String.fetchOne($0, sql: "SELECT value FROM sync_state WHERE key = ?", arguments: [key.rawValue]) }
    }

    /// nil deletes the key.
    public func setSyncState(_ values: [SyncStateKey: String?]) throws {
        try db.write { db in
            for (key, value) in values { try SyncStateStore.set(db, key, value) }
        }
    }

    /// Outbox rows are written only while signed in (`accountId` set) and not paused (`pendingAccountChoice` unset).
    public func isOutboxActive() throws -> Bool { try db.read(SyncStateStore.outboxActive) }

    /// Up to `maxRecords` records from the outbox: `*` rows carry every synced field, others only the listed fields;
    /// envelope fields (`owner`, `deleted`, `mergedInto`, `schema`, `type`) always.
    public func pendingPush(maxRecords: Int = 500) throws -> PushBatch { try db.read { try Outbox.batch($0, maxRecords: maxRecords) } }

    /// Deletes the rows of acked records whose clock still equals the sent one (rows re-written meanwhile stay).
    public func acknowledge(_ rows: [OutboxRow], acked: Set<ToriID>) throws {
        try db.write { try Outbox.acknowledge($0, rows: rows, acked: acked) }
    }

    /// Distinct record IDs in the outbox (sign-out note, §12.7).
    public func pendingRecordCount() throws -> Int {
        try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(DISTINCT record_id) FROM pending_changes") ?? 0 }
    }

    /// Sign-in / "Add to this account": every synced record pending as `*` (§12.5).
    public func markAllPending() throws { try db.write(Outbox.markAll) }

    public func clearOutbox() throws { try db.write { try $0.execute(sql: "DELETE FROM pending_changes") } }

    /// §11.5 step 2: if the HLC is more than 1 h ahead of `lastServerTime`, reset it and re-stamp every pending field
    /// (same value and rank, new clock, also in `field_clocks`). Returns whether a reset happened.
    @discardableResult
    public func recoverClockAhead(lastServerTime: Int64) throws -> Bool {
        try write { tx in try Outbox.recoverClockAhead(tx, lastServerTime: lastServerTime) }
    }

    /// §11.6: apply one pulled page and store `cursor`, in one transaction.
    @discardableResult
    public func applyPulledPage(_ records: [SyncRecord], cursor: String) throws -> PulledPageResult {
        try write { tx in
            let result = try Apply.page(tx, records)
            try SyncStateStore.set(tx.db, .cursor, cursor)
            return result
        }
    }

    /// Live (not deleted, not merged) synced user records beyond the defaults — the guard's "N" basis (§12.5).
    public func liveEntryCount() throws -> Int {
        try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM entry WHERE deleted = 0 AND merged_into IS NULL") ?? 0 }
    }
}

enum SyncStateStore {
    static func get(_ db: Database, _ key: SyncStateKey) throws -> String? {
        try String.fetchOne(db, sql: "SELECT value FROM sync_state WHERE key = ?", arguments: [key.rawValue])
    }

    static func set(_ db: Database, _ key: SyncStateKey, _ value: String?) throws {
        if let value {
            try db.execute(sql: "INSERT OR REPLACE INTO sync_state (key, value) VALUES (?, ?)", arguments: [key.rawValue, value])
        } else {
            try db.execute(sql: "DELETE FROM sync_state WHERE key = ?", arguments: [key.rawValue])
        }
    }

    static func outboxActive(_ db: Database) throws -> Bool {
        try get(db, .accountId) != nil && get(db, .pendingAccountChoice) == nil
    }
}
