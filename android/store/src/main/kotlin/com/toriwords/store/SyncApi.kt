package com.toriwords.store

import com.toriwords.core.SyncRecord
import com.toriwords.core.ToriId
import com.toriwords.store.Sql.Companion.idArgs
import com.toriwords.store.Sql.Companion.ph

/** `sync_state` keys (doc 38 §11.4). */
enum class SyncStateKey(val key: String) {
    DRIVE_ACCOUNT("driveAccount"),
    /** Setting it to null also clears `drive_file*` (every nil-token reset drops the file index). */
    PAGE_TOKEN("pageToken"),
    GENERATION("generation"),
    GENERATION_CREATED_TIME("generationCreatedTime"),
    /** "1" after Drive data was deleted: the outbox stops until "Back up this device again". */
    DRIVE_DELETED("driveDeleted"),
    DEVICE_SEQ("deviceSeq"),
    SNAPSHOT_N("snapshotN"),
    HLC("hlc"),
    LAST_SERVER_TIME("lastServerTime"),
    LAST_SYNC_AT("lastSyncAt"),
    /** JSON `{appVersion, ids}`: records refused, excluded from pushes until the app version changes. */
    EXCLUDED_RECORDS("excludedRecords"),
}

/** One outbox row. `*` = whole record; `_deleted` / `_mergedInto` = envelope changes; `_cloudDelete` = Drive purge owner. */
data class OutboxRow(val recordId: ToriId, val type: String, val field: String, val clock: String)

/** Full envelopes of the pending records, plus the rows they cover (pass them back to [recordSaved]). */
data class PushBatch(val records: List<SyncRecord>, val rows: List<OutboxRow>)

data class PulledPageResult(
    /** Records of a type this version does not know (kept in Drive, skipped here). */
    val skippedUnknownTypes: Set<String>,
)

/** One indexed Drive file; `owners` null = not known (file skipped on a nil-token fetch), existing owners kept. */
data class DriveFileIndex(val file: DriveFile, val owners: List<DriveFileOwner>?)

// The API the Drive sync engine calls. Every method is one transaction.

suspend fun ToriStore.syncState(key: SyncStateKey): String? = readSql { SyncStateStore.get(it, key) }

/** null deletes the key. */
suspend fun ToriStore.setSyncState(values: Map<SyncStateKey, String?>) {
    writeRaw { sql -> for ((k, v) in values) SyncStateStore.set(sql, k, v) }
}

/** Outbox rows are written while `driveAccount` is set and `driveDeleted` is unset. */
suspend fun ToriStore.isOutboxActive(): Boolean = readSql { SyncStateStore.outboxActive(it) }

/** Up to `maxRecords` pending records as full envelopes, excluding `_cloudDelete` rows. */
suspend fun ToriStore.pendingPush(maxRecords: Int = 300, excluding: Set<ToriId> = emptySet()): PushBatch =
    readSql { Outbox.batch(it, maxRecords, excluding) }

/**
 * The batch file holding these rows was uploaded (all-or-nothing): rows whose clock still equals the sent one go (rows
 * re-written meanwhile stay); acked Entry tombstones purge their group's children and queue the group as purge owners.
 * `index` records the uploaded file in the same transaction.
 */
suspend fun ToriStore.recordSaved(rows: List<OutboxRow>, index: List<DriveFileIndex> = emptyList()) {
    writeRaw { sql ->
        DriveIndex.upsert(sql, index)
        Outbox.acknowledge(sql, rows)
    }
}

/** Distinct record IDs in the outbox (unsynced changes). */
suspend fun ToriStore.pendingRecordCount(): Int =
    readSql { (it.long("SELECT COUNT(DISTINCT record_id) FROM pending_changes") ?: 0L).toInt() }

/** Every synced record pending as `*`. */
suspend fun ToriStore.markAllPending() = write { Outbox.markAll(it) }

/**
 * Clock-ahead check: if the HLC is more than 1 h ahead of `lastServerTime`, reset it and re-stamp every pending field
 * (same value and rank, new clock, also in `field_clocks`). Returns whether a reset happened.
 */
suspend fun ToriStore.recoverClockAhead(lastServerTime: Long): Boolean = write { Outbox.recoverClockAhead(it, lastServerTime) }

/**
 * One applied chunk, in one transaction: merge the records, purge locally the hidden children the cloud no longer has
 * (`deletedIds`), index the files, store `token` (null = keep). Live children of deleted Entries ("purge on sight") and
 * Entry groups a pulled tombstone deleted are queued as Drive purge owners. The engine passes ≤ 400 records per call.
 */
suspend fun ToriStore.applyCloudChanges(
    records: List<SyncRecord>,
    token: String? = null,
    index: List<DriveFileIndex> = emptyList(),
    deletedIds: List<ToriId> = emptyList(),
): PulledPageResult = write { tx ->
    tx.pulled = true
    val result = Apply.page(tx, records)
    Purge.hiddenChildren(tx.sql, deletedIds)
    if (tx.outboxActive) for (owner in result.droppedOwners) Outbox.queueCloudDelete(tx.sql, owner)
    DriveIndex.upsert(tx.sql, index)
    if (token != null) SyncStateStore.set(tx.sql, SyncStateKey.PAGE_TOKEN, token)
    PulledPageResult(result.skipped)
}

/** Entry owners whose envelopes still have to be purged from Drive. */
suspend fun ToriStore.pendingCloudDeletes(limit: Int = 300): List<ToriId> = readSql {
    it.ids("SELECT record_id FROM pending_changes WHERE field = ? ORDER BY record_id LIMIT ?", Outbox.CLOUD_DELETE, limit)
}

suspend fun ToriStore.cloudDeletesDone(owners: List<ToriId>) {
    writeRaw { sql ->
        sql.exec("DELETE FROM pending_changes WHERE field = ? AND record_id IN ${ph(owners.size)}", Outbox.CLOUD_DELETE, idArgs(owners))
    }
}

/**
 * First Drive sign-in or an account switch (the silent merge): `driveAccount = account`; pageToken (and the file index),
 * generation and `driveDeleted` cleared; every record pending.
 */
suspend fun ToriStore.activateDrive(account: String) = write { tx ->
    SyncStateStore.reset(tx.sql, SyncStateKey.GENERATION, SyncStateKey.GENERATION_CREATED_TIME, SyncStateKey.DRIVE_DELETED)
    SyncStateStore.set(tx.sql, SyncStateKey.DRIVE_ACCOUNT, account)
    Outbox.markAll(tx)
}

/** Drive data deleted (here or on another device): stop the outbox, forget token and file index; words stay. */
suspend fun ToriStore.markDriveDeleted() {
    writeRaw { sql ->
        SyncStateStore.reset(sql)
        SyncStateStore.set(sql, SyncStateKey.DRIVE_DELETED, "1")
        sql.exec("DELETE FROM pending_changes")
    }
}

/** "Back up this device again": `driveDeleted` cleared, pageToken/generation reset, everything pending. */
suspend fun ToriStore.backUpAgain() = write { tx ->
    SyncStateStore.reset(tx.sql, SyncStateKey.GENERATION, SyncStateKey.GENERATION_CREATED_TIME, SyncStateKey.DRIVE_DELETED)
    Outbox.markAll(tx)
}

/** Live (not deleted, not merged) Entries. */
suspend fun ToriStore.liveEntryCount(): Int =
    readSql { (it.long("SELECT COUNT(*) FROM entry WHERE deleted = 0 AND merged_into IS NULL") ?: 0L).toInt() }

private suspend fun <T> ToriStore.readSql(body: suspend (Sql) -> T): T = read { body(it.sql) }

internal object SyncStateStore {
    suspend fun get(sql: Sql, key: SyncStateKey): String? = sql.text("SELECT value FROM sync_state WHERE key = ?", key.key)

    suspend fun set(sql: Sql, key: SyncStateKey, value: String?) {
        if (value != null) {
            sql.exec("INSERT OR REPLACE INTO sync_state (key, value) VALUES (?, ?)", key.key, value)
        } else {
            sql.exec("DELETE FROM sync_state WHERE key = ?", key.key)
            if (key == SyncStateKey.PAGE_TOKEN) DriveIndex.clear(sql)
        }
    }

    /** Nil-token reset (pageToken and file index) plus `also`. */
    suspend fun reset(sql: Sql, vararg also: SyncStateKey) {
        for (key in listOf(SyncStateKey.PAGE_TOKEN) + also) set(sql, key, null)
    }

    suspend fun outboxActive(sql: Sql): Boolean = get(sql, SyncStateKey.DRIVE_ACCOUNT) != null && get(sql, SyncStateKey.DRIVE_DELETED) == null
}

/** `drive_file` / `drive_file_owner` writes inside store transactions (the DAO serves reads outside them). */
internal object DriveIndex {
    suspend fun upsert(sql: Sql, index: List<DriveFileIndex>) {
        for ((f, owners) in index) {
            sql.exec(
                """INSERT OR REPLACE INTO drive_file (file_id, name, kind, device_id, layout, generation, modified_time, applied, has_unknown, pending_delete)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                f.file_id, f.name, f.kind, f.device_id, f.layout, f.generation, f.modified_time, f.applied, f.has_unknown, f.pending_delete,
            )
            if (owners == null) continue
            sql.exec("DELETE FROM drive_file_owner WHERE file_id = ?", f.file_id)
            for (o in owners) sql.exec("INSERT OR REPLACE INTO drive_file_owner (file_id, owner, has_live) VALUES (?, ?, ?)", f.file_id, o.owner, o.has_live)
        }
    }

    suspend fun clear(sql: Sql) {
        sql.exec("DELETE FROM drive_file_owner")
        sql.exec("DELETE FROM drive_file")
    }
}
