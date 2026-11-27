package com.toriwords.sync

import com.toriwords.core.Envelope
import com.toriwords.core.SyncRecord
import com.toriwords.core.ToriId

/**
 * In-memory Drive `appDataFolder` for tests: one namespace per Google account, files with fileIds and non-unique names,
 * created/modified times from the fake clock, `changes.list` paging (latest change per file, `removed` entries) with
 * tokens invalidated on demand, in-place rewrites, scripted errors and a hook that runs right before the next upload.
 */
class DriveFake(private val clock: () -> Long) {
    enum class Op { About, StartToken, Changes, List, Download, Create, Update, Delete }

    class Stored(var file: DriveFile, var bytes: ByteArray)
    class Change(val seq: Int, val fileId: String, val removed: Boolean)

    class Space {
        internal var epoch = 0
        internal var seq = 0
        val files = LinkedHashMap<String, Stored>()
        internal val changes = mutableListOf<Change>()
    }

    private val spaces = mutableMapOf<String, Space>()
    private val errors = mutableMapOf<Op, ArrayDeque<DriveError>>()
    private var counter = 0
    private var beforeUpload: (suspend () -> Unit)? = null

    /** Max changes per `changes.list` page and files per `files.list` page. */
    var pageLimit = 100
    val calls = mutableListOf<Op>()

    fun space(account: String): Space = spaces.getOrPut(account) { Space() }
    fun exists(account: String): Boolean = account in spaces

    /** One device's authorized Drive client. `online = false` fails every call with [DriveError.Network]. */
    inner class Link(var account: String, var displayName: String? = account) : DriveApi {
        var online = true

        private fun <T> run(op: Op, body: (Space) -> T): T {
            calls += op
            if (!online) throw DriveError.Network
            errors[op]?.removeFirstOrNull()?.let { throw it }
            return body(space(account))
        }

        override suspend fun about() = run(Op.About) { DriveUser(account, displayName, "$account@example.com") }

        override suspend fun getStartPageToken() = run(Op.StartToken) { "${it.epoch}:${it.seq}" }

        override suspend fun changesList(pageToken: String) = run(Op.Changes) { s ->
            val parts = pageToken.split(":").mapNotNull { it.toIntOrNull() }
            if (parts.size != 2 || parts[0] != s.epoch) throw DriveError.TokenExpired
            val latest = s.changes.filter { it.seq > parts[1] }.associateBy { it.fileId }.values.sortedBy { it.seq }
            val page = latest.take(pageLimit)
            val more = latest.size > page.size
            val items = page.map { c -> DriveChange(c.fileId, c.removed, if (c.removed) null else s.files[c.fileId]?.file) }
            val last = "${s.epoch}:${page.lastOrNull()?.seq ?: parts[1]}"
            DrivePage(items, if (more) last else null, if (more) null else "${s.epoch}:${s.seq}")
        }

        override suspend fun filesList(pageToken: String?) = run(Op.List) { s ->
            val from = pageToken?.toInt() ?: 0
            val all = s.files.values.map { it.file }
            val page = all.drop(from).take(pageLimit)
            DrivePage(page, if (from + page.size < all.size) "${from + page.size}" else null, null)
        }

        override suspend fun download(fileId: String) = run(Op.Download) { s -> s.files[fileId]?.bytes ?: throw DriveError.NotFound }

        override suspend fun create(name: String, appProperties: Map<String, String>, bytes: ByteArray): DriveFile {
            beforeUpload?.let {
                beforeUpload = null
                it()
            }
            return run(Op.Create) { s -> add(s, name, appProperties, bytes) }
        }

        override suspend fun updateMedia(fileId: String, bytes: ByteArray) = run(Op.Update) { s ->
            val stored = s.files[fileId] ?: throw DriveError.NotFound
            stored.bytes = bytes
            stored.file = stored.file.copy(modifiedTime = clock())
            s.changes += Change(++s.seq, fileId, removed = false)
            stored.file
        }

        override suspend fun delete(fileId: String) = run(Op.Delete) { s -> remove(s, fileId) }
    }

    // Scripting

    /** The next `times` calls of `op` (any account) fail with `error`. */
    fun fail(op: Op, error: DriveError, times: Int = 1) {
        repeat(times) { errors.getOrPut(op) { ArrayDeque() }.addLast(error) }
    }

    /** Runs `body` once, right before the next upload (another device writing between this device's pull and push). */
    fun beforeNextUpload(body: suspend () -> Unit) {
        beforeUpload = body
    }

    /** Every stored page token of `account` becomes invalid (410). */
    fun invalidateTokens(account: String) {
        space(account).epoch++
    }

    /** A file written by another client (a newer app version, a racing device): stored as-is. */
    fun put(account: String, name: String, appProperties: Map<String, String>, bytes: ByteArray): DriveFile =
        add(space(account), name, appProperties, bytes)

    /** "Delete hidden app data" in Drive settings. */
    fun deleteAll(account: String) {
        val s = space(account)
        for (id in s.files.keys.toList()) remove(s, id)
    }

    // Inspection

    fun files(account: String): List<Stored> = spaces[account]?.files?.values?.toList().orEmpty()

    /** Every layout-1 record file's envelopes, folded per id with the envelope merge. */
    fun records(account: String): Map<ToriId, SyncRecord> {
        val out = LinkedHashMap<ToriId, SyncRecord>()
        for (f in files(account).filter { it.file.isRecordFile && it.file.layout == 1 }) {
            for (r in DriveFormat.Body.decode(f.bytes).records()) out[r.id] = out[r.id]?.let { Envelope.merge(it, r) } ?: r
        }
        return out
    }

    /** Every envelope in every layout-1 record file, unmerged. */
    fun envelopes(account: String): List<SyncRecord> =
        files(account).filter { it.file.isRecordFile && it.file.layout == 1 }.flatMap { DriveFormat.Body.decode(it.bytes).records() }

    private fun add(s: Space, name: String, appProperties: Map<String, String>, bytes: ByteArray): DriveFile {
        val now = clock()
        val file = DriveFile("file-${(++counter).toString().padStart(5, '0')}", name, appProperties, now, now, trashed = false)
        s.files[file.id] = Stored(file, bytes)
        s.changes += Change(++s.seq, file.id, removed = false)
        return file
    }

    private fun remove(s: Space, fileId: String) {
        s.files.remove(fileId) ?: throw DriveError.NotFound
        s.changes += Change(++s.seq, fileId, removed = true)
    }
}
