import Foundation
import GRDB
import ToriCore

/// `sync_state` keys.
public enum SyncStateKey: String, CaseIterable, Sendable {
    case cursor, hlc, accountId, lastSyncedAccountId, pendingAccountChoice, adoptedAccountId, lastServerTime, lastSyncAt,
         signInBaseline, lastProvider,
         /// JSON `{appVersion, ids}`: records the server rejected (`invalid_record` / `too_large`), excluded from pushes
         /// until the app version changes.
         excludedRecords
}

/// One outbox row. `field == "*"` = the whole record; `_deleted` / `_mergedInto` = envelope changes.
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

    public init(records: [SyncRecord], rows: [OutboxRow]) {
        self.records = records
        self.rows = rows
    }
}

public struct PulledPageResult: Sendable, Equatable {
    /// Records of a type this version does not know (for a later backfill).
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
    public func pendingPush(maxRecords: Int = 500, excluding: Set<ToriID> = []) throws -> PushBatch {
        try db.read { try Outbox.batch($0, maxRecords: maxRecords, excluding: excluding) }
    }

    /// Deletes the rows of acked records whose clock still equals the sent one (rows re-written meanwhile stay).
    public func acknowledge(_ rows: [OutboxRow], acked: Set<ToriID>) throws {
        try db.write { try Outbox.acknowledge($0, rows: rows, acked: acked) }
    }

    /// Distinct record IDs in the outbox (sign-out note).
    public func pendingRecordCount() throws -> Int {
        try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(DISTINCT record_id) FROM pending_changes") ?? 0 }
    }

    /// Sign-in / "Add to this account": every synced record pending as `*`.
    public func markAllPending() throws { try write(Outbox.markAll) }

    public func clearOutbox() throws { try db.write { try $0.execute(sql: "DELETE FROM pending_changes") } }

    /// Clock-ahead check: if the HLC is more than 1 h ahead of `lastServerTime`, reset it and re-stamp every pending field
    /// (same value and rank, new clock, also in `field_clocks`). Returns whether a reset happened.
    @discardableResult
    public func recoverClockAhead(lastServerTime: Int64) throws -> Bool {
        try write { tx in try Outbox.recoverClockAhead(tx, lastServerTime: lastServerTime) }
    }

    /// Apply one pulled page and store `cursor`, in one transaction.
    @discardableResult
    public func applyPulledPage(_ records: [SyncRecord], cursor: String) throws -> PulledPageResult {
        try write { tx in
            let result = try Apply.page(tx, records)
            try SyncStateStore.set(tx.db, .cursor, cursor)
            return result
        }
    }

    /// Sign-in without a foreign account / account prompt "Add": persist the account and mark every record pending, one transaction.
    /// `adopted` = the account the local data was adopted into ("Add"); clears `pendingAccountChoice`.
    public func beginSyncing(account: String, adopted: Bool) throws {
        try write { tx in
            try SyncStateStore.set(tx.db, .accountId, account)
            try SyncStateStore.set(tx.db, .pendingAccountChoice, nil)
            if adopted { try SyncStateStore.set(tx.db, .adoptedAccountId, account) }
            try Outbox.markAll(tx)
        }
    }

    /// Sign-out, session loss, account deletion: `accountId`, cursor, `adoptedAccountId`,
    /// `pendingAccountChoice` and the outbox gone; data and `lastSyncedAccountId` kept.
    public func enterLocalOnly() throws { try db.write(Account.signedOutState) }

    /// The device holds synced user records beyond the deterministic defaults (LanguagePair, Settings, Device).
    public func hasUserRecordsBeyondDefaults() throws -> Bool {
        try db.read { db in
            for type in RecordType.all where ![RecordType.languagePair, .settings, .device].contains(type) {
                if try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM \(type.name))") == true { return true }
            }
            return false
        }
    }

    /// Live canonical Entries with every Entry ID of their merge group (merge summary).
    public func liveEntryGroups() throws -> [ToriID: Set<ToriID>] {
        try db.read { db in
            var groups: [ToriID: Set<ToriID>] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT m.id, m.canonical_id FROM entry m JOIN entry c ON c.id = m.canonical_id
                WHERE c.deleted = 0 AND c.merged_into IS NULL
                """) {
                groups[row["canonical_id"], default: []].insert(row["id"])
            }
            return groups
        }
    }

    /// Live (not deleted, not merged) synced user records beyond the defaults — the account prompt's "N".
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
