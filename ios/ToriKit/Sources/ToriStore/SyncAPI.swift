import Foundation
import GRDB
import ToriCore

/// `sync_state` keys.
public enum SyncStateKey: String, CaseIterable, Sendable {
    case hlc, lastServerTime, lastSyncAt,
         /// JSON `{appVersion, ids}`: records the cloud refused, excluded from pushes until the app version changes.
         excludedRecords,
         /// The iCloud user record name the local data is synced with; set on first availability or a switch.
         cloudUser,
         /// Base64 of the archived zone change token.
         changeToken,
         /// "1" once the zone was created (or found) for `cloudUser`.
         zoneCreated,
         /// The `zone-info` generation adopted for `cloudUser`'s zone.
         zoneGeneration,
         /// "1" after iCloud data was deleted (here or elsewhere): the outbox stops until "Back up this device again".
         cloudDeleted
}

/// One outbox row. `field == "*"` = the whole record; `_deleted` / `_mergedInto` = envelope changes;
/// `_cloudDelete` = a purged child record still to be deleted from the cloud.
public struct OutboxRow: Hashable, Sendable {
    public var recordID: ToriID
    public var type: String
    public var field: String
    public var clock: String
}

/// Full envelopes of the pending records, plus the rows they cover (pass them back to `recordSaved`).
public struct PushBatch: Sendable {
    public var records: [SyncRecord]
    public var rows: [OutboxRow]

    public init(records: [SyncRecord], rows: [OutboxRow]) {
        self.records = records
        self.rows = rows
    }
}

public struct PulledPageResult: Sendable, Equatable {
    /// Records of a type this version does not know (kept in the cloud, skipped here).
    public var skippedUnknownTypes: Set<String>
}

/// The API ToriSync calls. Every method is one transaction.
extension ToriStore {
    public func syncState(_ key: SyncStateKey) throws -> String? {
        try db.read { try SyncStateStore.get($0, key) }
    }

    /// nil deletes the key.
    public func setSyncState(_ values: [SyncStateKey: String?]) throws {
        try db.write { db in
            for (key, value) in values { try SyncStateStore.set(db, key, value) }
        }
    }

    /// Outbox rows are written while `cloudUser` is set and `cloudDeleted` is unset (iCloud temporarily off keeps queueing).
    public func isOutboxActive() throws -> Bool { try db.read(SyncStateStore.outboxActive) }

    /// Up to `maxRecords` pending records as full envelopes (every synced field), excluding `_cloudDelete` rows.
    public func pendingPush(maxRecords: Int = 300, excluding: Set<ToriID> = []) throws -> PushBatch {
        try db.read { try Outbox.batch($0, maxRecords: maxRecords, excluding: excluding) }
    }

    /// Saved records: their rows whose clock still equals the sent one go (rows re-written meanwhile stay), the new
    /// system fields are stored, and acked Entry tombstones purge their group's children (queued as cloud deletes).
    public func recordSaved(_ rows: [OutboxRow], meta: [ToriID: Data]) throws {
        try db.write { db in
            try CloudMeta.store(db, meta)
            try Outbox.acknowledge(db, rows: rows, acked: Set(meta.keys))
        }
    }

    /// Distinct record IDs in the outbox (unsynced changes).
    public func pendingRecordCount() throws -> Int {
        try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(DISTINCT record_id) FROM pending_changes") ?? 0 }
    }

    /// Every synced record pending as `*`.
    public func markAllPending() throws { try write(Outbox.markAll) }

    /// Clock-ahead check: if the HLC is more than 1 h ahead of `lastServerTime`, reset it and re-stamp every pending field
    /// (same value and rank, new clock, also in `field_clocks`). Returns whether a reset happened.
    @discardableResult
    public func recoverClockAhead(lastServerTime: Int64) throws -> Bool {
        try write { tx in try Outbox.recoverClockAhead(tx, lastServerTime: lastServerTime) }
    }

    /// One fetched page (or the server copies of conflicting saves, `token: nil`), in one transaction: merge the records,
    /// store their system fields, purge locally the hidden children the cloud deleted, store `token`.
    /// Live children of deleted Entries ("purge on sight") and the children of Entry groups a pulled tombstone deleted
    /// are queued as cloud deletes.
    @discardableResult
    public func applyCloudChanges(_ records: [SyncRecord], meta: [ToriID: Data] = [:], deletedIDs: [ToriID] = [],
                                  token: String?) throws -> PulledPageResult {
        try write { tx in
            tx.pulled = true
            let result = try Apply.page(tx, records)
            try CloudMeta.store(tx.db, meta.filter { id, _ in result.dropped[id] == nil })
            try Purge.hiddenChildren(tx.db, deletedIDs)
            if tx.outboxActive {
                for (id, type) in result.dropped { try Outbox.queueCloudDelete(tx.db, id, type) }
            }
            if let token { try SyncStateStore.set(tx.db, .changeToken, token) }
            return PulledPageResult(skippedUnknownTypes: result.skipped)
        }
    }

    /// Stored system fields of these records (records without are saved as new cloud records).
    public func cloudMeta(_ ids: [ToriID]) throws -> [ToriID: Data] {
        try db.read { db in
            var out: [ToriID: Data] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT record_id, system_fields FROM cloud_record_meta WHERE record_id IN \(Database.placeholders(ids.count))",
                                        arguments: idArgs(ids)) {
                out[row["record_id"]] = row["system_fields"]
            }
            return out
        }
    }

    /// `unknownItem`: the stored system fields point to a record the cloud no longer has.
    public func dropCloudMeta(_ ids: [ToriID]) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM cloud_record_meta WHERE record_id IN \(Database.placeholders(ids.count))", arguments: idArgs(ids))
        }
    }

    /// Purged children still to be deleted from the cloud.
    public func pendingCloudDeletes(limit: Int = 300) throws -> [ToriID] {
        try db.read {
            try ToriID.fetchAll($0, sql: "SELECT record_id FROM pending_changes WHERE field = ? ORDER BY record_id LIMIT ?",
                                arguments: [Outbox.cloudDelete, limit])
        }
    }

    public func cloudDeletesDone(_ ids: [ToriID]) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM pending_changes WHERE field = ? AND record_id IN \(Database.placeholders(ids.count))",
                           arguments: StatementArguments([Outbox.cloudDelete]) + idArgs(ids))
            try db.execute(sql: "DELETE FROM cloud_record_meta WHERE record_id IN \(Database.placeholders(ids.count))", arguments: idArgs(ids))
        }
    }

    /// First iCloud availability or an iCloud account switch (the silent merge): `cloudUser = user`; token, system fields,
    /// zone keys and `cloudDeleted` cleared; every record pending.
    public func activateCloud(user: String) throws {
        try write { tx in
            try CloudMeta.reset(tx.db, also: [.zoneCreated, .zoneGeneration, .cloudDeleted])
            try SyncStateStore.set(tx.db, .cloudUser, user)
            try Outbox.markAll(tx)
        }
    }

    /// iCloud data deleted (here or on another device): stop the outbox, forget token and system fields; words stay.
    public func markCloudDeleted() throws {
        try db.write { db in
            try CloudMeta.reset(db)
            try SyncStateStore.set(db, .cloudDeleted, "1")
            try db.execute(sql: "DELETE FROM pending_changes")
        }
    }

    /// "Back up this device again": a new (or the other devices' re-created) zone generation and everything pending.
    public func backUpAgain() throws {
        try write { tx in
            try CloudMeta.reset(tx.db, also: [.zoneCreated, .zoneGeneration, .cloudDeleted])
            try Outbox.markAll(tx)
        }
    }

    /// Live (not deleted, not merged) Entries.
    public func liveEntryCount() throws -> Int {
        try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM entry WHERE deleted = 0 AND merged_into IS NULL") ?? 0 }
    }
}

/// `cloud_record_meta`: archived CloudKit system fields per record.
enum CloudMeta {
    static func store(_ db: Database, _ meta: [ToriID: Data]) throws {
        for (id, data) in meta {
            try db.execute(sql: "INSERT OR REPLACE INTO cloud_record_meta (record_id, system_fields) VALUES (?, ?)", arguments: [id, data])
        }
    }

    /// Token and system fields gone (the next fetch is a full one, every save a fresh record), plus `also`.
    static func reset(_ db: Database, also keys: [SyncStateKey] = []) throws {
        try db.execute(sql: "DELETE FROM cloud_record_meta")
        for key in [.changeToken] + keys { try SyncStateStore.set(db, key, nil) }
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
        try get(db, .cloudUser) != nil && get(db, .cloudDeleted) == nil
    }
}
