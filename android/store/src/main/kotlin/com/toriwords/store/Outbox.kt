package com.toriwords.store

import com.toriwords.core.HlcState
import com.toriwords.core.SyncRecord
import com.toriwords.core.ToriId
import com.toriwords.store.Sql.Companion.idArgs
import com.toriwords.store.Sql.Companion.ph

/** Outbox reads and bookkeeping. */
internal object Outbox {
    /** Field of a row asking for a Drive purge of an Entry owner (doc 38 §11.2 Purge). */
    const val CLOUD_DELETE = "_cloudDelete"

    /** Full envelopes: a partial change still sends every field (files hold whole merged records). */
    suspend fun batch(sql: Sql, maxRecords: Int, excluding: Set<ToriId>): PushBatch {
        val ids = sql.rows(
            """SELECT record_id, MIN(type) AS type FROM pending_changes
            WHERE field != '$CLOUD_DELETE' AND record_id NOT IN ${ph(excluding.size)}
            GROUP BY record_id ORDER BY record_id LIMIT ?""",
            idArgs(excluding), maxRecords,
        )
        val records = ArrayList<SyncRecord>()
        val rows = ArrayList<OutboxRow>()
        for (r in ids) {
            val id = r.id("record_id")!!
            val typeName = r.str("type")!!
            sql.rows("SELECT field, clock FROM pending_changes WHERE record_id = ? AND field != ?", id, CLOUD_DELETE)
                .mapTo(rows) { OutboxRow(id, typeName, it.str("field")!!, it.str("clock")!!) }
            val type = RecordType.BY_NAME[typeName] ?: continue
            RecordIO.load(sql, type, id)?.let(records::add)
        }
        return PushBatch(records, rows)
    }

    /** Rows whose clock still equals the sent one go; acked Entry tombstones purge their group's children. */
    suspend fun acknowledge(sql: Sql, rows: List<OutboxRow>) {
        val tombstones = HashSet<ToriId>()
        for (row in rows) {
            sql.exec("DELETE FROM pending_changes WHERE record_id = ? AND field = ? AND clock = ?", row.recordId, row.field, row.clock)
            if (row.type == "entry") tombstones.add(row.recordId)
        }
        if (tombstones.isNotEmpty()) Purge.deletedEntries(sql, tombstones, queueCloudDeletes = true)
    }

    suspend fun dropPending(sql: Sql, id: ToriId) = sql.exec("DELETE FROM pending_changes WHERE record_id = ?", id)

    /** Queues a Drive purge of `entry` (an owner); its own pending rows are superseded. */
    suspend fun queueCloudDelete(sql: Sql, entry: ToriId) {
        dropPending(sql, entry)
        sql.exec("INSERT INTO pending_changes (record_id, type, field, clock) VALUES (?, 'entry', ?, '')", entry, CLOUD_DELETE)
    }

    suspend fun markAll(tx: Tx) {
        val clock = tx.stamp().toString()
        for (type in RecordType.ALL) {
            tx.sql.exec(
                "INSERT OR REPLACE INTO pending_changes (record_id, type, field, clock) SELECT id, ?, '*', ? FROM ${type.name}",
                type.name, clock,
            )
        }
    }

    suspend fun recoverClockAhead(tx: Tx, lastServerTime: Long): Boolean {
        if (tx.hlc.ms - lastServerTime <= HlcState.HOUR_MS) return false
        tx.hlc = HlcState(maxOf(lastServerTime, tx.now), 0)
        val rows = tx.sql.rows("SELECT record_id, type, field FROM pending_changes WHERE field != ? ORDER BY record_id, field", CLOUD_DELETE)
        for (row in rows) {
            val id = row.id("record_id")!!
            val field = row.str("field")!!
            val clock = tx.stamp()
            tx.sql.exec("UPDATE pending_changes SET clock = ? WHERE record_id = ? AND field = ?", clock.toString(), id, field)
            val type = RecordType.BY_NAME[row.str("type")] ?: continue
            val record = RecordIO.load(tx.sql, type, id) ?: continue
            val names = if (field == "*") record.fields.keys else setOf(field)
            val fields = LinkedHashMap(record.fields)
            for (name in names) fields[name]?.let { fields[name] = it.copy(clock = clock) }
            RecordIO.store(tx.sql, type, record.copy(fields = fields))
        }
        return true
    }
}

/** Applying a pulled page (doc 36 steps 1–10 per record). */
internal object Apply {
    enum class Outcome { INSERTED, UPDATED, UNCHANGED, DROPPED }

    class PageResult(val skipped: Set<String>, val droppedOwners: Set<ToriId>)

    /** `droppedOwners`: deleted owner Entries of live children seen in the page (purge on sight). */
    suspend fun page(tx: Tx, records: List<SyncRecord>): PageResult {
        val skipped = HashSet<String>()
        val dropped = LinkedHashSet<ToriId>()
        for (remote in records) {
            val type = RecordType.BY_NAME[remote.type]
            if (type == null) {
                skipped.add(remote.type)
                continue
            }
            if (record(tx, type, remote) == Outcome.DROPPED && !remote.deleted) remote.owner?.let(dropped::add)
        }
        return PageResult(skipped, dropped)
    }

    suspend fun record(tx: Tx, type: RecordType, remote: SyncRecord): Outcome {
        for (f in remote.fields.values) tx.hlc.receive(f.clock, tx.now)
        val owner = remote.owner
        if (owner != null && type.ownerColumn != null && ownerDeleted(tx.sql, owner)) return Outcome.DROPPED
        val local = RecordIO.load(tx.sql, type, remote.id)
        val merged = local?.let { SyncRecord.merge(it, remote) } ?: remote
        if (merged == local) return Outcome.UNCHANGED
        tx.storeLocal(type, merged, before = local)
        // A newer value on a merged loser reaches the survivor.
        val into = merged.mergedInto
        if (into != null && !merged.deleted && type.mergeable && (merged.fields != local?.fields || local.mergedInto == null)) {
            val survivor = tx.sql.id("SELECT canonical_id FROM ${type.name} WHERE id = ?", into) ?: into
            DuplicateMerge.absorb(tx, type, merged, survivor)
        }
        return if (local == null) Outcome.INSERTED else Outcome.UPDATED
    }

    /** The owning Entry (or its canonical survivor) is known and deleted. */
    suspend fun ownerDeleted(sql: Sql, owner: ToriId): Boolean = sql.bool(
        """SELECT EXISTS (SELECT 1 FROM entry e LEFT JOIN entry c ON c.id = e.canonical_id
        WHERE e.id = ? AND (e.deleted = 1 OR c.deleted = 1))""",
        owner,
    )
}
