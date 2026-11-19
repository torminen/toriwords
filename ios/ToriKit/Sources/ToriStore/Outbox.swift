import Foundation
import GRDB
import ToriCore

/// Outbox reads and bookkeeping.
enum Outbox {
    /// Field of a row that asks for the cloud deletion of a purged child record.
    static let cloudDelete = "_cloudDelete"

    /// Full envelopes: the cloud stores whole merged records, so a partial change still sends every field.
    static func batch(_ db: Database, maxRecords: Int, excluding: Set<ToriID>) throws -> PushBatch {
        let ids = try Row.fetchAll(db, sql: """
            SELECT record_id, MIN(type) AS type FROM pending_changes
            WHERE field != '\(cloudDelete)' AND record_id NOT IN \(Database.placeholders(excluding.count))
            GROUP BY record_id ORDER BY record_id LIMIT ?
            """, arguments: idArgs(excluding) + [maxRecords])
        var records: [SyncRecord] = [], rows: [OutboxRow] = []
        for r in ids {
            let id: ToriID = r["record_id"]
            let typeName: String = r["type"]
            let pending = try Row.fetchAll(db, sql: "SELECT field, clock FROM pending_changes WHERE record_id = ? AND field != ?",
                                           arguments: [id, cloudDelete]).map {
                OutboxRow(recordID: id, type: typeName, field: $0["field"], clock: $0["clock"])
            }
            rows += pending
            guard let type = RecordType.byName[typeName], let record = try RecordIO.load(db, type, id) else { continue }
            records.append(record)
        }
        return PushBatch(records: records, rows: rows)
    }

    static func acknowledge(_ db: Database, rows: [OutboxRow], acked: Set<ToriID>) throws {
        var tombstones = Set<ToriID>()
        for row in rows where acked.contains(row.recordID) {
            try db.execute(sql: "DELETE FROM pending_changes WHERE record_id = ? AND field = ? AND clock = ?",
                           arguments: [row.recordID, row.field, row.clock])
            if row.type == "entry" { tombstones.insert(row.recordID) }
        }
        if !tombstones.isEmpty { try Purge.deletedEntries(db, among: tombstones, queueCloudDeletes: true) }
    }

    static func queueCloudDelete(_ db: Database, _ id: ToriID, _ type: String) throws {
        try db.execute(sql: "DELETE FROM pending_changes WHERE record_id = ?", arguments: [id])
        try db.execute(sql: "INSERT INTO pending_changes (record_id, type, field, clock) VALUES (?, ?, ?, '')",
                       arguments: [id, type, cloudDelete])
    }

    static func markAll(_ tx: Tx) throws {
        let clock = tx.stamp().description
        for type in RecordType.all {
            try tx.db.execute(sql: "INSERT OR REPLACE INTO pending_changes (record_id, type, field, clock) SELECT id, ?, '*', ? FROM \(type.name)",
                              arguments: [type.name, clock])
        }
    }

    static func recoverClockAhead(_ tx: Tx, lastServerTime: Int64) throws -> Bool {
        guard tx.hlc.ms - lastServerTime > HLCState.hourMs else { return false }
        tx.hlc = HLCState(ms: max(lastServerTime, tx.now), counter: 0)
        let rows = try Row.fetchAll(tx.db, sql: "SELECT record_id, type, field FROM pending_changes WHERE field != ? ORDER BY record_id, field",
                                    arguments: [cloudDelete])
        for row in rows {
            let id: ToriID = row["record_id"], field: String = row["field"]
            let clock = tx.stamp()
            try tx.db.execute(sql: "UPDATE pending_changes SET clock = ? WHERE record_id = ? AND field = ?",
                              arguments: [clock.description, id, field])
            guard let type = RecordType.byName[row["type"]], var record = try RecordIO.load(tx.db, type, id) else { continue }
            let names = field == "*" ? Array(record.fields.keys) : [field]
            for name in names where record.fields[name] != nil { record.fields[name]!.clock = clock }
            try RecordIO.store(tx.db, type, record)
        }
        return true
    }
}

/// Applying a pulled page; also used by restore.
enum Apply {
    /// `dropped`: live children of deleted Entries (id -> type), for the cloud purge on sight.
    static func page(_ tx: Tx, _ records: [SyncRecord]) throws -> (skipped: Set<String>, dropped: [ToriID: String]) {
        var skipped = Set<String>(), dropped: [ToriID: String] = [:]
        for remote in records {
            guard let type = RecordType.byName[remote.type] else { skipped.insert(remote.type); continue }
            if try record(tx, type, remote) == .dropped, !remote.deleted { dropped[remote.id] = type.name }
        }
        return (skipped, dropped)
    }

    /// Merges one record; returns the outcome for restore statistics.
    @discardableResult
    static func record(_ tx: Tx, _ type: RecordType, _ remote: SyncRecord) throws -> Outcome {
        for f in remote.fields.values { tx.hlc.receive(f.clock, now: tx.now) }
        if let owner = remote.owner, type.ownerColumn != nil, try ownerDeleted(tx.db, owner) { return .dropped }
        let local = try RecordIO.load(tx.db, type, remote.id)
        let merged = local.map { SyncRecord.merge(local: $0, remote: remote) } ?? remote
        guard merged != local else { return .unchanged }
        try tx.storeLocal(type, merged, before: local)
        // A newer value on a merged loser reaches the survivor.
        if let into = merged.mergedInto, !merged.deleted, type.mergeable,
           merged.fields != local?.fields || local?.mergedInto == nil {
            let survivor = try ToriID.fetchOne(tx.db, sql: "SELECT canonical_id FROM \(type.name) WHERE id = ?", arguments: [into]) ?? into
            try DuplicateMerge.absorb(tx, type, from: merged, into: survivor)
        }
        return local == nil ? .inserted : .updated
    }

    enum Outcome { case inserted, updated, unchanged, dropped }

    /// The owning Entry (or its canonical survivor) is known and deleted.
    static func ownerDeleted(_ db: Database, _ owner: ToriID) throws -> Bool {
        try Bool.fetchOne(db, sql: """
            SELECT EXISTS (SELECT 1 FROM entry e LEFT JOIN entry c ON c.id = e.canonical_id
            WHERE e.id = ? AND (e.deleted = 1 OR c.deleted = 1))
            """, arguments: [owner]) ?? false
    }
}
