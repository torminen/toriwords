import Foundation
import GRDB
import ToriCore

/// One write transaction: HLC state, outbox flag and the set of records touched, for `finish()`.
final class Tx {
    let db: Database
    let now: Int64
    var hlc: HLCState
    var node: UInt64
    let outboxActive: Bool
    private var rng = SystemRandomNumberGenerator()

    /// Records whose synced state changed in this transaction, by type name.
    var touched: [String: Set<ToriID>] = [:]
    /// Canonical Cards to replay fully.
    var replay: Set<ToriID> = []
    /// Canonical Cards already advanced incrementally (answer commit).
    var stepped: Set<ToriID> = []
    var paramsChanged = false
    /// Applying cloud records: Entry tombstones that arrive purge their group's children (queued as cloud deletes).
    var pulled = false

    init(db: Database, now: Int64) throws {
        self.db = db
        self.now = now
        hlc = JSONText.decode(HLCState.self, try SyncStateStore.get(db, .hlc)) ?? HLCState()
        node = try ToriID.fetchOne(db, sql: "SELECT id FROM device WHERE is_this_device = 1")?.high ?? 0
        outboxActive = try SyncStateStore.outboxActive(db)
    }

    func newID() -> ToriID { ToriID.v7(unixMs: now, using: &rng) }
    func stamp() -> HLCTimestamp { hlc.localWrite(now: now, node: node) }

    func touch(_ type: RecordType, _ id: ToriID) { touched[type.name, default: []].insert(id) }

    func outbox(_ type: RecordType, _ id: ToriID, _ field: String, _ clock: HLCTimestamp) throws {
        guard outboxActive else { return }
        try db.execute(sql: "INSERT OR REPLACE INTO pending_changes (record_id, type, field, clock) VALUES (?, ?, ?, ?)",
                       arguments: [id, type.name, field, clock.description])
    }

    // MARK: Local writes (clocked, outboxed)

    /// Writes `fields` with one new clock and `rank`; creates the record if absent (`owner` fixed at creation).
    /// Fields whose value is unchanged and whose rank would not rise are skipped (no clock churn).
    @discardableResult
    func set(_ type: RecordType, _ id: ToriID, _ fields: [String: WireValue], rank: AuthorRank) throws -> Bool {
        var record = try RecordIO.load(db, type, id)
            ?? SyncRecord(id: id, type: type.name, schema: 1, owner: nil, deleted: false, mergedInto: nil, fields: [:])
        guard !record.deleted else { return false }
        // An automatic write never overrides a user value (enrichment never overwrites user edits).
        let changed = fields.filter { name, value in
            guard let old = record.fields[name] else { return true }
            return rank >= old.rank && (old.value != value || old.rank < rank)
        }
        guard !changed.isEmpty else { return false }
        let clock = stamp()
        for (name, value) in changed { record.fields[name] = FieldVersion(value: value, clock: clock, rank: rank) }
        if record.owner == nil, let col = type.ownerColumn, case .string(let s)? = record.fields[col]?.value {
            record.owner = ToriID(s)
        }
        try storeLocal(type, record)
        for name in changed.keys { try outbox(type, id, name, clock) }
        return true
    }

    /// Tombstone (delete wins): field values dropped, `_deleted` pushed.
    func delete(_ type: RecordType, _ id: ToriID) throws {
        guard var record = try RecordIO.load(db, type, id), !record.deleted else { return }
        record.deleted = true
        record.fields = [:]
        try storeLocal(type, record)
        try outbox(type, id, "_deleted", stamp())
    }

    /// Stores and marks touched; detects scheduler parameter changes.
    func storeLocal(_ type: RecordType, _ record: SyncRecord, before: SyncRecord? = nil) throws {
        if type == .settings {
            let old = try before ?? RecordIO.load(db, type, record.id)
            if ["fsrs_w", "desired_retention", "scheduler_version"].contains(where: { old?.fields[$0]?.value != record.fields[$0]?.value }) {
                paramsChanged = true
            }
        }
        try RecordIO.store(db, type, record)
        touch(type, record.id)
    }

    // MARK: Finish

    /// Post-write maintenance (canonical IDs, duplicate merge, cards, replay), then persist the HLC.
    func finish() throws {
        var rounds = 0
        repeat {
            try Canonical.resolve(self)
            try Canonical.propagateTombstones(self)
            rounds += 1
        } while try DuplicateMerge.run(self) && rounds < 16
        try Cards.createMissing(self)
        try Canonical.resolve(self)
        try Replay.run(self)
        if let deleted = touched["entry"], !deleted.isEmpty, !outboxActive || pulled {
            try Purge.deletedEntries(db, among: deleted, queueCloudDeletes: outboxActive)
        }
        try SyncStateStore.set(db, .hlc, JSONText.encode(hlc))
        touched = [:]
    }
}

extension Database {
    /// `(?, ?, …)` for an IN clause.
    static func placeholders(_ n: Int) -> String { "(" + Array(repeating: "?", count: max(n, 1)).joined(separator: ",") + ")" }
}

func idArgs(_ ids: some Collection<ToriID>) -> StatementArguments {
    ids.isEmpty ? [Data()] : StatementArguments(ids.map { $0 as DatabaseValueConvertible })
}
