import Foundation
import GRDB
import ToriCore

/// Canonical-ID resolution and child re-linking.
enum Canonical {
    static let mergeable: [RecordType] = [.entry, .sense, .context, .tag, .source]

    static func resolve(_ tx: Tx) throws {
        let db = tx.db
        var changed: [String: Set<ToriID>] = [:]
        for type in mergeable {
            let touched = tx.touched[type.name] ?? []
            guard !touched.isEmpty else { continue }
            var into: [ToriID: ToriID] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT id, merged_into FROM \(type.name) WHERE merged_into IS NOT NULL") {
                into[row["id"]] = row["merged_into"]
            }
            func end(_ id: ToriID) -> ToriID {
                var cur = id
                for _ in 0..<64 { guard let next = into[cur] else { break }; cur = next }
                return cur
            }
            let check = touched.union(into.keys)
            let current = try Row.fetchAll(db, sql: "SELECT id, canonical_id FROM \(type.name) WHERE id IN \(Database.placeholders(check.count))",
                                           arguments: idArgs(check))
            for row in current {
                let id: ToriID = row["id"]
                let target = end(id)
                if row["canonical_id"] as ToriID? != target {
                    try db.execute(sql: "UPDATE \(type.name) SET canonical_id = ? WHERE id = ?", arguments: [target, id])
                    changed[type.name, default: []].insert(id)
                }
            }
        }

        let entries = (tx.touched["entry"] ?? []).union(changed["entry"] ?? [])
        for child in ["sense", "context", "card", "entry_tag"] {
            let own = tx.touched[child] ?? []
            guard !entries.isEmpty || !own.isEmpty else { continue }
            try db.execute(sql: """
                UPDATE \(child) SET canonical_entry_id = (SELECT canonical_id FROM entry WHERE entry.id = \(child).entry_id)
                WHERE entry_id IN \(Database.placeholders(entries.count)) OR id IN \(Database.placeholders(own.count))
                """, arguments: idArgs(entries) + idArgs(own))
        }

        let tags = (tx.touched["tag"] ?? []).union(changed["tag"] ?? []), links = tx.touched["entry_tag"] ?? []
        if !tags.isEmpty || !links.isEmpty {
            try db.execute(sql: """
                UPDATE entry_tag SET canonical_tag_id = (SELECT canonical_id FROM tag WHERE tag.id = entry_tag.tag_id)
                WHERE tag_id IN \(Database.placeholders(tags.count)) OR id IN \(Database.placeholders(links.count))
                """, arguments: idArgs(tags) + idArgs(links))
        }

        // Cards: canonical Card = v5(card:canonicalEntry:direction); every change replays old and new.
        let touchedCards = tx.touched["card"] ?? []
        var relinked = touchedCards
        if !entries.isEmpty || !touchedCards.isEmpty {
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, direction, canonical_entry_id, canonical_card_id FROM card
                WHERE entry_id IN \(Database.placeholders(entries.count)) OR id IN \(Database.placeholders(touchedCards.count))
                """, arguments: idArgs(entries) + idArgs(touchedCards))
            for row in rows {
                let id: ToriID = row["id"], old: ToriID? = row["canonical_card_id"]
                let new = (row["canonical_entry_id"] as ToriID?).flatMap { e in
                    (row["direction"] as String?).flatMap(CardDirection.init(rawValue:)).map { ToriID.card(entry: e, direction: $0) }
                }
                if let new { tx.replay.insert(new) }
                if old != new {
                    try db.execute(sql: "UPDATE card SET canonical_card_id = ? WHERE id = ?", arguments: [new, id])
                    if let old { tx.replay.insert(old) }
                    relinked.insert(id)
                }
            }
        }
        let logs = tx.touched["review_log"] ?? []
        if !relinked.isEmpty || !logs.isEmpty {
            try db.execute(sql: """
                UPDATE review_log SET canonical_card_id = (SELECT canonical_card_id FROM card WHERE card.id = review_log.card_id)
                WHERE card_id IN \(Database.placeholders(relinked.count)) OR id IN \(Database.placeholders(logs.count))
                """, arguments: idArgs(relinked) + idArgs(logs))
            if !logs.isEmpty {
                let ids = try ToriID.fetchAll(db, sql: """
                    SELECT DISTINCT canonical_card_id FROM review_log
                    WHERE canonical_card_id IS NOT NULL AND id IN \(Database.placeholders(logs.count))
                    """, arguments: idArgs(logs))
                tx.replay.formUnion(ids)
            }
        }
    }

    /// A merge group is deleted when any member carries a tombstone: write it on the live survivor.
    static func propagateTombstones(_ tx: Tx) throws {
        for type in mergeable where !(tx.touched[type.name] ?? []).isEmpty {
            let survivors = try ToriID.fetchAll(tx.db, sql: """
                SELECT DISTINCT canonical_id FROM \(type.name) t WHERE deleted = 1 AND merged_into IS NOT NULL
                AND EXISTS (SELECT 1 FROM \(type.name) s WHERE s.id = t.canonical_id AND s.deleted = 0)
                """)
            for id in survivors { try tx.delete(type, id) }
        }
        // A deleted Entry group: its other Entries become value-less tombstones too (the cloud keeps no values of the group).
        guard !(tx.touched[RecordType.entry.name] ?? []).isEmpty else { return }
        for id in try ToriID.fetchAll(tx.db, sql: """
            SELECT m.id FROM entry m JOIN entry c ON c.id = m.canonical_id WHERE m.deleted = 0 AND m.id != c.id AND c.deleted = 1
            """) { try tx.delete(.entry, id) }
    }
}

/// Deterministic duplicate merge. Returns whether anything merged (the caller repeats until stable).
enum DuplicateMerge {
    static let live = "deleted = 0 AND merged_into IS NULL"

    static func run(_ tx: Tx) throws -> Bool {
        var merged = false
        let db = tx.db
        let touchedEntries = tx.touched["entry"] ?? []

        // Entries: canonical LanguagePair + match key.
        let keys = try Row.fetchAll(db, sql: """
            SELECT DISTINCT language_pair_id, match_key FROM entry
            WHERE \(live) AND match_key IS NOT NULL AND id IN \(Database.placeholders(touchedEntries.count))
            """, arguments: idArgs(touchedEntries))
        for k in keys {
            let ids = try ToriID.fetchAll(db, sql: """
                SELECT id FROM entry WHERE \(live) AND language_pair_id IS ? AND match_key = ? ORDER BY id
                """, arguments: [k["language_pair_id"] as DatabaseValue, k["match_key"] as String])
            merged = try merge(tx, .entry, ids) || merged
        }

        // Children of affected canonical Entries.
        let affected = try affectedEntries(tx)
        for e in affected {
            let senses = try Row.fetchAll(db, sql: "SELECT id, translation, definition FROM sense WHERE \(live) AND canonical_entry_id = ? ORDER BY id",
                                          arguments: [e])
            merged = try mergeGroups(tx, .sense, senses) { row in
                let t = TextKey.matchKey(row["translation"] ?? "")
                if !t.isEmpty { return "t:" + t }
                let d = TextKey.matchKey(row["definition"] ?? "")
                return d.isEmpty ? nil : "d:" + d
            } || merged
            let contexts = try Row.fetchAll(db, sql: """
                SELECT c.id, c.sentence, c.source_id, s.canonical_id AS source FROM context c LEFT JOIN source s ON s.id = c.source_id
                WHERE c.deleted = 0 AND c.merged_into IS NULL AND c.canonical_entry_id = ? ORDER BY c.id
                """, arguments: [e])
            merged = try mergeGroups(tx, .context, contexts) { row in
                TextKey.sentenceKey(row["sentence"] ?? "") + "|" + ((row["source"] as ToriID?)?.description ?? (row["source_id"] as ToriID?)?.description ?? "-")
            } || merged
        }

        // Tags: tag key.
        let touchedTags = tx.touched["tag"] ?? []
        if !touchedTags.isEmpty {
            let tags = try Row.fetchAll(db, sql: """
                SELECT id, name_key FROM tag WHERE \(live) AND name_key IN
                (SELECT name_key FROM tag WHERE id IN \(Database.placeholders(touchedTags.count))) ORDER BY id
                """, arguments: idArgs(touchedTags))
            merged = try mergeGroups(tx, .tag, tags) { $0["name_key"] } || merged
        }

        // Sources without URL: title match key + app (+ kind when suggested).
        if !(tx.touched["source"] ?? []).isEmpty {
            let sources = try Row.fetchAll(db, sql: "SELECT id, kind, title, app FROM source WHERE \(live) AND url IS NULL ORDER BY id")
            merged = try mergeGroups(tx, .source, sources) { row in
                let k = SourceKey(title: row["title"], app: row["app"], isSuggested: row["kind"] == "suggested")
                return "\(k.title)\u{0}\(k.app ?? "")\u{0}\(k.suggested)"
            } || merged
        }
        return merged
    }

    /// Canonical Entries whose children may hold new duplicates.
    static func affectedEntries(_ tx: Tx) throws -> Set<ToriID> {
        var result = Set<ToriID>()
        let entries = tx.touched["entry"] ?? []
        result.formUnion(try ToriID.fetchAll(tx.db, sql: "SELECT canonical_id FROM entry WHERE id IN \(Database.placeholders(entries.count))",
                                             arguments: idArgs(entries)))
        for child in ["sense", "context"] {
            let ids = tx.touched[child] ?? []
            result.formUnion(try ToriID.fetchAll(tx.db, sql: """
                SELECT canonical_entry_id FROM \(child) WHERE canonical_entry_id IS NOT NULL AND id IN \(Database.placeholders(ids.count))
                """, arguments: idArgs(ids)))
        }
        let sources = tx.touched["source"] ?? []
        result.formUnion(try ToriID.fetchAll(tx.db, sql: """
            SELECT canonical_entry_id FROM context WHERE canonical_entry_id IS NOT NULL AND source_id IN \(Database.placeholders(sources.count))
            """, arguments: idArgs(sources)))
        return result
    }

    /// Rows must be ordered by ID; nil key = never merged.
    static func mergeGroups(_ tx: Tx, _ type: RecordType, _ rows: [Row], key: (Row) -> String?) throws -> Bool {
        var groups: [String: [ToriID]] = [:]
        for row in rows { if let k = key(row) { groups[k, default: []].append(row["id"]) } }
        var merged = false
        for ids in groups.values { merged = try merge(tx, type, ids) || merged }
        return merged
    }

    /// Survivor = smallest ID; losers get `merged_into` (rank 0, outbox) and the survivor takes their winning fields.
    static func merge(_ tx: Tx, _ type: RecordType, _ ids: [ToriID]) throws -> Bool {
        guard let survivor = ids.min(), ids.count > 1 else { return false }
        for loser in ids where loser != survivor {
            guard var record = try RecordIO.load(tx.db, type, loser) else { continue }
            record.mergedInto = survivor
            try tx.storeLocal(type, record)
            try tx.outbox(type, loser, "_mergedInto", tx.stamp())
            try absorb(tx, type, from: record, into: survivor)
        }
        return true
    }

    /// Field merge into the survivor: original clocks and ranks copied, no outbox. The owner never changes.
    static func absorb(_ tx: Tx, _ type: RecordType, from loser: SyncRecord, into survivorID: ToriID) throws {
        guard var survivor = try RecordIO.load(tx.db, type, survivorID), !survivor.deleted else { return }
        var changed = false
        for (name, f) in loser.fields where name != type.ownerColumn {
            if let s = survivor.fields[name], !f.wins(over: s) { continue }
            survivor.fields[name] = f
            changed = true
        }
        if changed { try tx.storeLocal(type, survivor) }
    }
}

/// Card creation for Entries that became reviewable, rank 0, deterministic IDs.
enum Cards {
    static func createMissing(_ tx: Tx) throws {
        let db = tx.db
        for e in try DuplicateMerge.affectedEntries(tx) {
            let reviewable = try Bool.fetchOne(db, sql: """
                SELECT EXISTS (SELECT 1 FROM entry WHERE id = ? AND \(DuplicateMerge.live) AND status = 'active')
                AND EXISTS (SELECT 1 FROM sense WHERE canonical_entry_id = ? AND \(DuplicateMerge.live) AND translation <> '')
                """, arguments: [e, e]) ?? false
            guard reviewable else { continue }
            var directions: [CardDirection] = [.recognition, .recall]
            if try Bool.fetchOne(db, sql: """
                SELECT EXISTS (SELECT 1 FROM context WHERE canonical_entry_id = ? AND \(DuplicateMerge.live)
                AND sentence IS NOT NULL AND highlight_offset IS NOT NULL)
                """, arguments: [e]) ?? false {
                directions.append(.cloze)
            }
            for d in directions {
                let id = ToriID.card(entry: e, direction: d)
                guard try !Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM card WHERE id = ?)", arguments: [id])! else { continue }
                try tx.set(.card, id, ["entry_id": .string(e.description), "direction": .string(d.rawValue),
                                       "created_at": .int(tx.now)], rank: .automatic)
            }
        }
    }
}

/// Card cache = replay of its canonical logs.
enum Replay {
    static func parameters(_ db: Database) throws -> (FSRSParameters, String) {
        let row = try Row.fetchOne(db, sql: "SELECT fsrs_w, desired_retention, params_id FROM settings WHERE id = ?", arguments: [ToriID.settings])
        let w = JSONText.decode([Double].self, row?["fsrs_w"]) ?? FSRSParameters.default.w
        let retention: Double = row?["desired_retention"] ?? FSRSParameters.default.desiredRetention
        let p = w.count == FSRSParameters.default.w.count ? FSRSParameters(w: w, desiredRetention: retention) : .default
        return (p, row?["params_id"] ?? "fsrs6-default-1")
    }

    static func run(_ tx: Tx) throws {
        let db = tx.db
        let cards = tx.paramsChanged
            ? Set(try ToriID.fetchAll(db, sql: "SELECT id FROM card WHERE id = canonical_card_id"))
            : tx.replay.subtracting(tx.stepped)
        guard !cards.isEmpty else { return }
        let (p, paramsID) = try parameters(db)
        for id in cards {
            let logs = try Row.fetchAll(db, sql: """
                SELECT id, reviewed_at, utc_offset_min, rating FROM review_log WHERE canonical_card_id = ? AND reviewed_at IS NOT NULL
                """, arguments: [id]).map { r in
                ReviewLogInput(id: r["id"], cardID: id, reviewedAt: r["reviewed_at"], utcOffsetMin: r["utc_offset_min"] ?? 0,
                               rating: (r["rating"] as Int?).flatMap(Rating.init(rawValue:)))
            }
            try writeCache(db, id, FSRS.replay(cardID: id, logs: logs, p), paramsID)
        }
        tx.replay = []
    }

    static func writeCache(_ db: Database, _ id: ToriID, _ s: CardState?, _ paramsID: String) throws {
        try db.execute(sql: """
            UPDATE card SET stability = ?, difficulty = ?, last_review_day = ?, due_day = ?, reps = ?, lapses = ?, stage = ?,
            params_id = ? WHERE id = ?
            """, arguments: [s?.stability, s?.difficulty, s?.lastReviewDay, s?.dueDay, s?.reps ?? 0, s?.lapses ?? 0,
                             (s?.stage ?? .new).rawValue, paramsID, id])
    }
}

/// Explicit purge of a deleted Entry's children; no cascades.
enum Purge {
    static let children = ["sense", "context", "card", "entry_tag"]

    /// Deletes the children of deleted Entries' groups (tombstones stay). `queueCloudDeletes`: the purged children are also
    /// queued for deletion from the cloud (sync active), replacing their outbox rows.
    static func deletedEntries(_ db: Database, among ids: Set<ToriID>, queueCloudDeletes: Bool = false) throws {
        let deleted = try ToriID.fetchAll(db, sql: """
            SELECT id FROM entry WHERE deleted = 1 AND id IN \(Database.placeholders(ids.count))
            AND NOT EXISTS (SELECT 1 FROM pending_changes WHERE record_id = entry.id AND field = '_deleted')
            """, arguments: idArgs(ids))
        guard !deleted.isEmpty else { return }
        let group = Set(deleted).union(try ToriID.fetchAll(db, sql: "SELECT id FROM entry WHERE canonical_id IN \(Database.placeholders(deleted.count))",
                                                          arguments: idArgs(deleted)))
        let ph = Database.placeholders(group.count)
        let owned: [(String, String)] = children.map { ($0, "entry_id IN \(ph) OR canonical_entry_id IN \(ph)") }
            + [("review_log", "owner_entry_id IN \(ph)")]
        for (table, condition) in owned {
            let args = table == "review_log" ? idArgs(group) : idArgs(group) + idArgs(group)
            if queueCloudDeletes {
                for id in try ToriID.fetchAll(db, sql: "SELECT id FROM \(table) WHERE \(condition)", arguments: args) {
                    try Outbox.queueCloudDelete(db, id, table)
                }
            }
            try db.execute(sql: "DELETE FROM \(table) WHERE \(condition)", arguments: args)
        }
    }

    /// Records the cloud deleted: only hidden children (owner Entry deleted) are purged here; anything else stays.
    static func hiddenChildren(_ db: Database, _ ids: [ToriID]) throws {
        guard !ids.isEmpty else { return }
        let ph = Database.placeholders(ids.count)
        for type in RecordType.all {
            guard let owner = type.ownerColumn else { continue }
            try db.execute(sql: """
                DELETE FROM \(type.name) WHERE id IN \(ph) AND EXISTS (SELECT 1 FROM entry e LEFT JOIN entry c ON c.id = e.canonical_id
                WHERE e.id = \(type.name).\(owner) AND (e.deleted = 1 OR c.deleted = 1))
                """, arguments: idArgs(ids))
        }
        try db.execute(sql: "DELETE FROM cloud_record_meta WHERE record_id IN \(ph)", arguments: idArgs(ids))
    }
}
