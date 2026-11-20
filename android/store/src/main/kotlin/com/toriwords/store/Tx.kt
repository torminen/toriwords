package com.toriwords.store

import com.toriwords.core.AuthorRank
import com.toriwords.core.FieldVersion
import com.toriwords.core.HlcState
import com.toriwords.core.HlcTimestamp
import com.toriwords.core.SyncRecord
import com.toriwords.core.ToriId
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlin.random.Random

/** One write transaction: HLC state, outbox flag and the set of records touched, for [finish]. */
internal class Tx private constructor(
    val sql: Sql,
    val now: Long,
    var hlc: HlcState,
    var node: ULong,
    val outboxActive: Boolean,
) {
    /** Records whose synced state changed in this transaction, by type name. */
    val touched = HashMap<String, MutableSet<ToriId>>()
    /** Canonical Cards to replay fully. */
    val replay = HashSet<ToriId>()
    /** Canonical Cards already advanced incrementally (answer commit). */
    val stepped = HashSet<ToriId>()
    var paramsChanged = false
    /** Applying cloud records: Entry tombstones that arrive purge their group's children (queued as cloud purges). */
    var pulled = false
    /** A local change entered the outbox (drives the debounced sync trigger). */
    var outboxed = false

    fun touched(type: RecordType): Set<ToriId> = touched[type.name] ?: emptySet()
    fun touched(name: String): Set<ToriId> = touched[name] ?: emptySet()

    fun newId(): ToriId = ToriId.v7(now, Random.Default)
    fun stamp(): HlcTimestamp = hlc.localWrite(now, node)

    fun touch(type: RecordType, id: ToriId) {
        touched.getOrPut(type.name) { HashSet() }.add(id)
    }

    suspend fun outbox(type: RecordType, id: ToriId, field: String, clock: HlcTimestamp) {
        if (!outboxActive) return
        outboxed = true
        sql.exec("INSERT OR REPLACE INTO pending_changes (record_id, type, field, clock) VALUES (?, ?, ?, ?)", id, type.name, field, clock.toString())
    }

    // Local writes (clocked, outboxed)

    /**
     * Writes `fields` with one new clock and `rank`; creates the record if absent (`owner` fixed at creation). Fields whose
     * value is unchanged and whose rank would not rise are skipped (no clock churn).
     */
    suspend fun set(type: RecordType, id: ToriId, fields: Map<String, JsonElement>, rank: AuthorRank): Boolean {
        val record = RecordIO.load(sql, type, id) ?: SyncRecord(id, type.name, 1, null, false, null, emptyMap())
        if (record.deleted) return false
        // An automatic write never overrides a user value (enrichment never overwrites user edits).
        val changed = fields.filter { (name, value) ->
            val old = record.fields[name] ?: return@filter true
            rank >= old.rank && (old.value != value || old.rank < rank)
        }
        if (changed.isEmpty()) return false
        val clock = stamp()
        val merged = LinkedHashMap(record.fields)
        for ((name, value) in changed) merged[name] = FieldVersion(value, clock, rank)
        var owner = record.owner
        if (owner == null) {
            owner = type.ownerColumn?.let { (merged[it]?.value as? JsonPrimitive)?.takeIf { p -> p.isString }?.content?.let(ToriId::parse) }
        }
        storeLocal(type, record.copy(owner = owner, fields = merged))
        for (name in changed.keys) outbox(type, id, name, clock)
        return true
    }

    /** Tombstone (delete wins): field values dropped, `_deleted` pushed. */
    suspend fun delete(type: RecordType, id: ToriId) {
        val record = RecordIO.load(sql, type, id) ?: return
        if (record.deleted) return
        storeLocal(type, record.copy(deleted = true, fields = emptyMap()))
        outbox(type, id, "_deleted", stamp())
    }

    /** Stores and marks touched; detects scheduler parameter changes. */
    suspend fun storeLocal(type: RecordType, record: SyncRecord, before: SyncRecord? = null) {
        if (type === RecordType.SETTINGS) {
            val old = before ?: RecordIO.load(sql, type, record.id)
            if (listOf("fsrs_w", "desired_retention", "scheduler_version").any { old?.fields?.get(it)?.value != record.fields[it]?.value }) {
                paramsChanged = true
            }
        }
        RecordIO.store(sql, type, record)
        touch(type, record.id)
    }

    /** Post-write maintenance (canonical IDs, duplicate merge, cards, replay), then persist the HLC. */
    suspend fun finish() {
        var rounds = 0
        do {
            Canonical.resolve(this)
            Canonical.propagateTombstones(this)
            rounds++
        } while (DuplicateMerge.run(this) && rounds < 16)
        Cards.createMissing(this)
        Canonical.resolve(this)
        Replay.run(this)
        val deleted = touched(RecordType.ENTRY)
        if (deleted.isNotEmpty() && (!outboxActive || pulled)) Purge.deletedEntries(sql, deleted, queueCloudDeletes = outboxActive)
        SyncStateStore.set(sql, SyncStateKey.HLC, encodeHlc(hlc))
        touched.clear()
    }

    companion object {
        suspend fun begin(sql: Sql, now: Long): Tx = Tx(
            sql, now, decodeHlc(SyncStateStore.get(sql, SyncStateKey.HLC)),
            sql.id("SELECT id FROM device WHERE is_this_device = 1")?.high ?: 0UL, SyncStateStore.outboxActive(sql),
        )

        /** `{"counter", "ms"}` (sorted keys, as iOS). */
        fun encodeHlc(h: HlcState): String =
            JsonText.json.encodeToString(JsonObject.serializer(), JsonObject(mapOf("counter" to JsonPrimitive(h.counter), "ms" to JsonPrimitive(h.ms))))

        fun decodeHlc(text: String?): HlcState = text?.let {
            runCatching {
                val o = JsonText.json.parseToJsonElement(it).jsonObject
                HlcState(o.getValue("ms").jsonPrimitive.long, o.getValue("counter").jsonPrimitive.int)
            }.getOrNull()
        } ?: HlcState()
    }
}
