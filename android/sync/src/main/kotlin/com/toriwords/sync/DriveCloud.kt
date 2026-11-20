package com.toriwords.sync

import com.toriwords.core.HlcState
import com.toriwords.core.SyncRecord
import com.toriwords.core.ToriId
import com.toriwords.store.DriveFileIndex
import com.toriwords.store.DriveFileOwner
import com.toriwords.store.RecordType
import com.toriwords.store.SyncStateKey
import com.toriwords.store.ToriStore
import com.toriwords.store.allRecords
import com.toriwords.store.applyCloudChanges
import com.toriwords.store.cloudDeletesDone
import com.toriwords.store.markAllPending
import com.toriwords.store.pendingCloudDeletes
import com.toriwords.store.pendingPush
import com.toriwords.store.recordSaved
import com.toriwords.store.setSyncState
import com.toriwords.store.syncState
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import com.toriwords.store.DriveFile as IndexedFile

/** Drive data was deleted (no `generation.json`, or a later one): stop syncing until "Back up this device again". */
internal class DriveDeleted : Exception()

/** The cycle was superseded by a reset (Turn off, Delete Drive data…, Back up again) while it was suspended. */
internal class Superseded : Exception()

/**
 * One sync cycle's Drive work (doc 38 §11.2): the `generation.json` rule, fetch, batch push, purge rewrite and
 * compaction over [DriveApi]. `check` runs after every suspension and throws [Superseded] when the cycle went stale.
 */
internal class DriveCloud(
    private val store: ToriStore,
    private val api: DriveApi,
    private val deviceId: String,
    private val appVersion: String,
    private val applyChunk: Int,
    private val now: () -> Long,
    private val newGeneration: () -> String,
    private val check: () -> Unit,
    private val onProgress: (Pair<Int, Int>?) -> Unit,
) {
    private val dao = store.database.driveFiles()
    private class Generation(val uuid: String, val createdTime: Long)
    private lateinit var current: Generation

    /** Set when an upload's `modifiedTime` was more than 1 h off this device's clock. */
    var clockWarning: Boolean? = null
        private set

    // Generation

    suspend fun prepareGeneration() {
        current = resolveGeneration(listAll())
    }

    private suspend fun resolveGeneration(files: List<DriveFile>): Generation {
        val markers = files.filter { it.kind == DriveFormat.GENERATION && it.layout == DriveFormat.LAYOUT }
            .sortedWith(compareBy<DriveFile> { it.createdTime }.thenBy { it.id })
        for (loser in markers.drop(1)) deleteIgnoringMissing(loser.id)
        val winner = markers.firstOrNull()
        val stored = store.syncState(SyncStateKey.GENERATION)
        val storedCreated = store.syncState(SyncStateKey.GENERATION_CREATED_TIME)?.toLongOrNull()
        if (stored == null) {
            if (winner == null) {
                createGeneration()
                return resolveGeneration(listAll()) // a concurrent creator may have won
            }
            return adopt(winner, markAll = false)
        }
        if (winner == null) throw DriveDeleted()
        if (winner.generation == stored) return Generation(stored, storedCreated ?: winner.createdTime)
        // Creation race: the winner existed first, so everything this device sent under the losing marker is re-sent.
        if (storedCreated != null && winner.createdTime <= storedCreated) return adopt(winner, markAll = true)
        throw DriveDeleted()
    }

    private suspend fun createGeneration(): DriveFile {
        val upload = DriveFormat.generation(newGeneration())
        return api.create(upload.name, upload.appProperties, upload.bytes).also { check() }
    }

    private suspend fun adopt(winner: DriveFile, markAll: Boolean): Generation {
        val uuid = winner.generation ?: throw DriveError.Other(0, "generation.json without generation")
        store.setSyncState(mapOf(SyncStateKey.GENERATION to uuid, SyncStateKey.GENERATION_CREATED_TIME to "${winner.createdTime}"))
        if (markAll) store.markAllPending()
        return Generation(uuid, winner.createdTime)
    }

    /** After each upload: a creation race is adopted silently; a real deletion removes the just-uploaded file. */
    private suspend fun recheckGeneration(uploaded: String) {
        try {
            current = resolveGeneration(listAll())
        } catch (e: DriveDeleted) {
            deleteIgnoringMissing(uploaded)
            throw e
        }
    }

    // Fetch

    suspend fun pull() {
        val token = store.syncState(SyncStateKey.PAGE_TOKEN)
        if (token == null) return nilTokenFetch()
        try {
            deltaFetch(token)
        } catch (_: DriveError.TokenExpired) {
            store.setSyncState(mapOf(SyncStateKey.PAGE_TOKEN to null))
            nilTokenFetch()
        }
    }

    private suspend fun deltaFetch(start: String) {
        var token = start
        while (true) {
            val page = api.changesList(token)
            check()
            val next = page.nextPageToken ?: page.newStartPageToken ?: token
            val gone = page.items.filter { it.removed || it.file == null || it.file.trashed }.map { it.fileId }
            if (gone.isNotEmpty()) dao.delete(gone)
            // Own files are skipped only here: a stored pageToken means this device already holds their content.
            val files = page.items.mapNotNull { c -> c.file?.takeIf { !c.removed && !it.trashed && it.isRecordFile && it.deviceId != deviceId } }
            if (files.isEmpty()) store.setSyncState(mapOf(SyncStateKey.PAGE_TOKEN to next))
            files.forEachIndexed { i, f -> applyFile(f, if (i == files.lastIndex) next else null) }
            if (page.nextPageToken == null) return
            token = page.nextPageToken
        }
    }

    private suspend fun nilTokenFetch() {
        val startToken = api.getStartPageToken()
        check()
        val files = listAll().filter { it.isRecordFile && it.layout == DriveFormat.LAYOUT }
        val live = files.filter { !isStray(it) }
        files.filter(::isStray).forEach { deleteIgnoringMissing(it.id) }
        val snapshot = newestCompleteSnapshot(live)
        val covered = snapshot?.covers.orEmpty().map { it.fileId }.toSet()
        val inSnapshot = snapshot?.parts.orEmpty().map { it.id }.toSet()
        val rest = live.filter { it.id !in covered && it.id !in inSnapshot }.sortedWith(compareBy<DriveFile> { it.createdTime }.thenBy { it.id })
        val ordered = snapshot?.parts.orEmpty() + rest
        // Covered files: indexed from metadata, owners read when a purge first needs them.
        val coveredIndex = live.filter { it.id in covered }.map { DriveFileIndex(it.indexed(applied = false), owners = null) }
        if (coveredIndex.isNotEmpty() || ordered.isEmpty()) store.applyCloudChanges(emptyList(), if (ordered.isEmpty()) startToken else null, coveredIndex)
        onProgress(0 to ordered.size)
        ordered.forEachIndexed { i, f ->
            applyFile(f, if (i == ordered.lastIndex) startToken else null)
            onProgress(i + 1 to ordered.size)
        }
        onProgress(null)
    }

    private class Snapshot(val parts: List<DriveFile>, val covers: List<DriveFormat.Cover>)

    private suspend fun newestCompleteSnapshot(files: List<DriveFile>): Snapshot? {
        val sets = files.filter { it.kind == DriveFormat.SNAPSHOT }
            .groupBy { it.deviceId to it.appProperties["n"] }.values
            .sortedByDescending { set -> set.maxOf { it.createdTime } }
        for (set in sets) {
            val first = set.firstOrNull { it.part == 0 } ?: continue
            val body = download(first.id) ?: continue
            val parts = (0 until body.parts).map { p -> set.firstOrNull { it.part == p } ?: break }
            if (parts.size == body.parts) return Snapshot(parts, body.covers)
        }
        return null
    }

    /** A file of another generation created before the current marker: an upload that raced a deletion. */
    private fun isStray(f: DriveFile) = f.generation != current.uuid && f.createdTime < current.createdTime

    /** Applies one file in chunks of ≤ [applyChunk] envelopes; `token` is stored with its last chunk. */
    private suspend fun applyFile(f: DriveFile, token: String?) {
        if (f.layout != DriveFormat.LAYOUT) return
        if (isStray(f)) return deleteIgnoringMissing(f.id)
        val body = download(f.id)
        if (body == null) {
            if (token != null) store.setSyncState(mapOf(SyncStateKey.PAGE_TOKEN to token))
            return
        }
        val records = body.records()
        val unknown = records.size != body.raw.size || records.any { it.type !in KNOWN_TYPES }
        val index = DriveFileIndex(f.indexed(applied = true, hasUnknown = unknown), DriveFileOwner.of(f.id, records))
        val chunks = records.chunked(applyChunk).ifEmpty { listOf(emptyList()) }
        chunks.forEachIndexed { i, chunk ->
            val last = i == chunks.lastIndex
            store.applyCloudChanges(chunk, if (last) token else null, if (last) listOf(index) else emptyList())
        }
        observeCloudTime(f.modifiedTime, fresh = false)
    }

    // Push

    suspend fun push() {
        var excluded = excludedRecords()
        var maxRecords = DriveFormat.MAX_BATCH_RECORDS
        while (true) {
            val batch = store.pendingPush(maxRecords, excluded)
            if (batch.records.isEmpty()) return
            val (fitting, oversized) = fit(batch.records)
            if (oversized.isNotEmpty()) {
                excluded = excluded + oversized
                saveExcluded(excluded)
                continue
            }
            val ids = fitting.map { it.id }.toSet()
            val rows = batch.rows.filter { it.recordId in ids }
            val seq = (store.syncState(SyncStateKey.DEVICE_SEQ)?.toLongOrNull() ?: 0) + 1
            store.setSyncState(mapOf(SyncStateKey.DEVICE_SEQ to "$seq"))
            val upload = DriveFormat.batch(current.uuid, deviceId, seq, fitting)
            val file = try {
                api.create(upload.name, upload.appProperties, upload.bytes)
            } catch (_: DriveError.TooLarge) {
                check()
                if (fitting.size > 1) {
                    maxRecords = maxOf(1, fitting.size / 2)
                } else {
                    excluded = excluded + ids
                    saveExcluded(excluded)
                }
                continue
            } catch (_: DriveError.Other) {
                check()
                excluded = excluded + ids
                saveExcluded(excluded)
                continue
            }
            check()
            store.recordSaved(rows, listOf(DriveFileIndex(file.indexed(applied = true), DriveFileOwner.of(file.id, fitting))))
            observeCloudTime(file.modifiedTime, fresh = true)
            recheckGeneration(file.id)
        }
    }

    /** Records within 64 KB, then as many as fit in 2 MB (encoded JSON). */
    private fun fit(records: List<SyncRecord>): Pair<List<SyncRecord>, Set<ToriId>> {
        var total = 0
        val fitting = mutableListOf<SyncRecord>()
        val oversized = mutableSetOf<ToriId>()
        for (r in records) {
            val size = DriveFormat.size(r)
            if (size > DriveFormat.MAX_RECORD_BYTES) {
                oversized += r.id
                continue
            }
            if (total + size > DriveFormat.MAX_BATCH_BYTES) break
            total += size
            fitting += r
        }
        return fitting to oversized
    }

    @Serializable
    private class Excluded(val appVersion: String, val ids: List<String>)

    private suspend fun excludedRecords(): Set<ToriId> {
        val text = store.syncState(SyncStateKey.EXCLUDED_RECORDS) ?: return emptySet()
        val value = runCatching { Json.decodeFromString<Excluded>(text) }.getOrNull() ?: return emptySet()
        return if (value.appVersion == appVersion) value.ids.mapNotNull(ToriId::parse).toSet() else emptySet()
    }

    private suspend fun saveExcluded(ids: Set<ToriId>) {
        val text = Json.encodeToString(Excluded.serializer(), Excluded(appVersion, ids.map { it.toString() }.sorted()))
        store.setSyncState(mapOf(SyncStateKey.EXCLUDED_RECORDS to text))
    }

    // Purge

    /** Rewrites in place every file holding envelopes of the queued Entry owners (raw JSON: unknown content survives). */
    suspend fun purge() {
        while (true) {
            val owners = store.pendingCloudDeletes(DriveFormat.MAX_BATCH_RECORDS)
            if (owners.isEmpty()) return
            for (f in dao.filesWithUnknownOwners()) {
                if (f.layout != DriveFormat.LAYOUT) continue
                val body = download(f.file_id) ?: continue
                dao.replaceOwners(f.file_id, DriveFileOwner.of(f.file_id, body.records()))
            }
            val ownerSet = owners.toSet()
            for (fileId in dao.filesHolding(owners.map { it.bytes })) {
                if (dao.file(fileId)?.layout != DriveFormat.LAYOUT) continue
                val body = download(fileId) ?: continue
                val rewritten = body.purged(ownerSet)
                if (rewritten == null) {
                    dao.replaceOwners(fileId, DriveFileOwner.of(fileId, body.records()))
                } else if (rewritten.raw.isEmpty()) {
                    deleteIgnoringMissing(fileId)
                    dao.delete(listOf(fileId))
                } else {
                    val updated = api.updateMedia(fileId, rewritten.encode())
                    check()
                    dao.replaceOwners(fileId, DriveFileOwner.of(fileId, rewritten.records()))
                    observeCloudTime(updated.modifiedTime, fresh = false)
                }
            }
            store.cloudDeletesDone(owners)
        }
    }

    // Compaction

    /** Covered files whose delete failed earlier (app killed, network): retried at the start of each cycle. */
    suspend fun retryPendingDeletes() {
        for (f in dao.pendingDeletes()) {
            deleteIgnoringMissing(f.file_id)
            dao.delete(listOf(f.file_id))
        }
    }

    // ponytail: "not covered by the newest snapshot" ≈ applied, indexed batch files; covered files are indexed unapplied.
    suspend fun compactIfDue() {
        val indexed = dao.all()
        if (indexed.count { it.kind == DriveFormat.BATCH && it.applied && it.layout == DriveFormat.LAYOUT } < COMPACTION_THRESHOLD) return
        val covers = indexed.filter { it.applied && !it.has_unknown && !it.pending_delete && it.layout == DriveFormat.LAYOUT && it.kind != DriveFormat.GENERATION }
        val records = store.read { it.allRecords() }
        val n = (store.syncState(SyncStateKey.SNAPSHOT_N)?.toLongOrNull() ?: 0) + 1
        store.setSyncState(mapOf(SyncStateKey.SNAPSHOT_N to "$n"))
        val parts = DriveFormat.snapshotParts(records)
        val coverList = covers.map { DriveFormat.Cover(it.file_id, it.name) }
        for ((i, part) in parts.withIndex()) {
            val upload = DriveFormat.snapshotPart(current.uuid, deviceId, n, i, parts.size, coverList, part)
            val file = api.create(upload.name, upload.appProperties, upload.bytes)
            check()
            store.applyCloudChanges(emptyList(), null, listOf(DriveFileIndex(file.indexed(applied = true), DriveFileOwner.of(file.id, part))))
            observeCloudTime(file.modifiedTime, fresh = true)
            recheckGeneration(file.id)
        }
        if (covers.isEmpty()) return
        dao.markPendingDelete(covers.map { it.file_id })
        retryPendingDeletes()
    }

    /** Every file in `appDataFolder` (Delete Drive data…). */
    suspend fun deleteAll() {
        for (f in listAll()) deleteIgnoringMissing(f.id)
    }

    // Helpers

    private suspend fun listAll(): List<DriveFile> {
        val out = mutableListOf<DriveFile>()
        var token: String? = null
        do {
            val page = api.filesList(token)
            check()
            out += page.items.filter { !it.trashed }
            token = page.nextPageToken
        } while (token != null)
        return out
    }

    /** Download 404 = compacted or purged away: skipped. */
    private suspend fun download(fileId: String): DriveFormat.Body? {
        val bytes = try {
            api.download(fileId)
        } catch (_: DriveError.NotFound) {
            check()
            dao.delete(listOf(fileId))
            return null
        }
        check()
        return DriveFormat.Body.decode(bytes)
    }

    private suspend fun deleteIgnoringMissing(fileId: String) {
        try {
            api.delete(fileId)
        } catch (_: DriveError.NotFound) {
        }
        check()
    }

    /** `lastServerTime` = the newest Drive `modifiedTime` seen; an own upload's time drives the clock warning. */
    private suspend fun observeCloudTime(modified: Long, fresh: Boolean) {
        if (modified <= 0) return
        if (modified > (store.syncState(SyncStateKey.LAST_SERVER_TIME)?.toLongOrNull() ?: 0)) {
            store.setSyncState(mapOf(SyncStateKey.LAST_SERVER_TIME to "$modified"))
        }
        if (fresh) clockWarning = kotlin.math.abs(now() - modified) > HlcState.HOUR_MS
    }

    private fun DriveFile.indexed(applied: Boolean, hasUnknown: Boolean = false) = IndexedFile(
        file_id = id, name = name, kind = kind ?: "", device_id = deviceId, layout = layout, generation = generation,
        modified_time = modifiedTime, applied = applied, has_unknown = hasUnknown,
    )

    companion object {
        const val COMPACTION_THRESHOLD = 200
        private val KNOWN_TYPES = RecordType.BY_NAME.keys
    }
}
