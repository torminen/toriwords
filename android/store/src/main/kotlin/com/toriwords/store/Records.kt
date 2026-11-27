package com.toriwords.store

import com.toriwords.core.AuthorRank
import com.toriwords.core.DayModel
import com.toriwords.core.FieldVersion
import com.toriwords.core.HlcTimestamp
import com.toriwords.core.SyncRecord
import com.toriwords.core.TextKey
import com.toriwords.core.ToriId
import com.toriwords.core.UrlKey
import com.toriwords.core.WireJson
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlin.math.abs
import kotlin.math.floor

/** How a synced column maps to the wire. */
enum class FieldKind {
    TEXT, INT, REAL, BOOL, ID, JSON;

    fun toWire(v: Any?): JsonElement {
        if (v == null) return JsonNull
        return when (this) {
            TEXT -> (v as? String)?.let(::JsonPrimitive) ?: JsonNull
            INT -> (v as? Long)?.let(::JsonPrimitive) ?: JsonNull
            REAL -> (v as? Number)?.let { jsonNumber(it.toDouble()) } ?: JsonNull
            BOOL -> JsonPrimitive(((v as? Long) ?: 0L) != 0L)
            ID -> (v as? ByteArray)?.takeIf { it.size == 16 }?.let { JsonPrimitive(ToriId.fromBytes(it).toString()) } ?: JsonNull
            JSON -> (v as? String)?.let { runCatching { JsonText.json.parseToJsonElement(it) }.getOrNull() } ?: JsonNull
        }
    }

    /** Lenient: a value of the wrong JSON type is stored as NULL rather than failing the page. */
    fun toDatabase(w: JsonElement): Any? {
        if (w is JsonNull) return null
        if (this == JSON) return JsonText.json.encodeToString(JsonElement.serializer(), w)
        val p = w as? JsonPrimitive ?: return null
        return when (this) {
            TEXT -> p.content.takeIf { p.isString }
            INT -> if (p.isString) null else p.longOrNull ?: p.doubleOrNull?.takeIf { floor(it) == it }?.toLong()
            REAL -> if (p.isString) null else p.doubleOrNull
            BOOL -> if (p.isString) null else p.booleanOrNull?.let { if (it) 1L else 0L } ?: p.longOrNull?.let { if (it != 0L) 1L else 0L }
            ID -> if (p.isString) ToriId.parse(p.content) else null
            JSON -> error("unreachable")
        }
    }

    companion object {
        /** Integral doubles print as integers, as the iOS encoder does (`10`, not `10.0`). */
        fun jsonNumber(d: Double): JsonPrimitive = if (floor(d) == d && abs(d) < 9.007199254740992E15) JsonPrimitive(d.toLong()) else JsonPrimitive(d)
    }
}

/** One synced record type: its table (= wire `type`), synced fields and owner column. */
class RecordType private constructor(val name: String, val fields: Map<String, FieldKind>, val ownerColumn: String?) {
    /** Types whose duplicates merge and that carry a `canonical_id`. */
    val mergeable: Boolean get() = name in setOf("entry", "sense", "context", "tag", "source")
    val fieldNames: List<String> = fields.keys.sorted()

    override fun toString(): String = name

    companion object {
        private val T = FieldKind.TEXT
        private val I = FieldKind.INT
        private val R = FieldKind.REAL
        private val B = FieldKind.BOOL
        private val D = FieldKind.ID

        val LANGUAGE_PAIR = RecordType("language_pair", mapOf("native_lang" to T, "target_lang" to T, "created_at" to I), null)
        val ENTRY = RecordType(
            "entry",
            mapOf(
                "language_pair_id" to D, "text" to T, "ipa" to T, "note" to T, "status" to T, "excluded_reason" to T,
                "enrichment_status" to T, "needs_check" to B, "origin" to T, "created_at" to I, "updated_at" to I,
            ),
            null,
        )
        val SENSE = RecordType(
            "sense",
            mapOf(
                "entry_id" to D, "translation" to T, "definition" to T, "part_of_speech" to T, "position" to R,
                "translation_src" to T, "definition_src" to T, "pos_src" to T, "dict_version" to T, "dict_headword_key" to T,
                "dict_sense_ordinal" to I,
            ),
            "entry_id",
        )
        val SOURCE = RecordType("source", mapOf("kind" to T, "url" to T, "title" to T, "app" to T), null)
        val CONTEXT = RecordType(
            "context",
            mapOf(
                "entry_id" to D, "sense_id" to D, "sentence" to T, "highlight_offset" to I, "highlight_length" to I,
                "source_id" to D, "captured_at" to I,
            ),
            "entry_id",
        )
        val CARD = RecordType("card", mapOf("entry_id" to D, "direction" to T, "import_ref" to T, "created_at" to I), "entry_id")
        val REVIEW_LOG = RecordType(
            "review_log",
            mapOf(
                "card_id" to D, "owner_entry_id" to D, "reviewed_at" to I, "utc_offset_min" to I, "rating" to I, "answer_ms" to I,
                "device_id" to D, "original_rating" to I, "import_ref" to T,
            ),
            "owner_entry_id",
        )
        val TAG = RecordType("tag", mapOf("name" to T), null)
        val ENTRY_TAG = RecordType("entry_tag", mapOf("entry_id" to D, "tag_id" to D, "present" to B), "entry_id")
        val SETTINGS = RecordType(
            "settings",
            mapOf(
                "new_words_per_day" to I, "desired_retention" to R, "fsrs_w" to FieldKind.JSON, "params_id" to T,
                "scheduler_version" to I,
            ),
            null,
        )
        val DEVICE = RecordType("device", mapOf("platform" to T, "display_name" to T, "first_seen" to I), null)

        /** Parents before children (export order and `markAllPending` order). */
        val ALL = listOf(LANGUAGE_PAIR, SETTINGS, DEVICE, ENTRY, SOURCE, TAG, SENSE, CONTEXT, CARD, ENTRY_TAG, REVIEW_LOG)
        val BY_NAME: Map<String, RecordType> = ALL.associateBy { it.name }
    }
}

/** `field_clocks` entry `{"c", "u"}`. */
internal data class FieldClock(val c: String, val u: Int)

internal object JsonText {
    val json = WireJson.json

    fun clocks(text: String?): Map<String, FieldClock> {
        val o = text?.let { runCatching { json.parseToJsonElement(it).jsonObject }.getOrNull() } ?: return emptyMap()
        return o.mapNotNull { (k, v) ->
            runCatching { FieldClock(v.jsonObject.getValue("c").jsonPrimitive.content, v.jsonObject.getValue("u").jsonPrimitive.int) }
                .getOrNull()?.let { k to it }
        }.toMap()
    }

    /** Sorted keys, so equal content is equal text. */
    fun encodeClocks(clocks: Map<String, FieldClock>): String = json.encodeToString(
        JsonObject.serializer(),
        JsonObject(clocks.toSortedMap().mapValues { JsonObject(mapOf("c" to JsonPrimitive(it.value.c), "u" to JsonPrimitive(it.value.u))) }),
    )

    fun extra(text: String?): Map<String, FieldVersion<JsonElement>> {
        val o = text?.let { runCatching { json.parseToJsonElement(it).jsonObject }.getOrNull() } ?: return emptyMap()
        return o.mapNotNull { (k, v) -> runCatching { WireJson.field(v) { it } }.getOrNull()?.let { k to it } }.toMap()
    }

    /** Unknown values stay raw JSON elements: they are written back exactly as received. */
    fun encodeExtra(extra: Map<String, FieldVersion<JsonElement>>): String =
        json.encodeToString(JsonObject.serializer(), JsonObject(extra.toSortedMap().mapValues { WireJson.field(it.value) { v -> v } }))
}

/** Envelope ↔ row. */
internal object RecordIO {
    /** The local record as an envelope (all fields with clocks plus `extra`); null if absent. */
    suspend fun load(sql: Sql, type: RecordType, id: ToriId): SyncRecord? =
        sql.row("SELECT * FROM ${type.name} WHERE id = ?", id)?.let { envelope(type, it) }

    fun envelope(type: RecordType, row: Row): SyncRecord {
        val fields = LinkedHashMap(JsonText.extra(row.str("extra")))
        for ((name, clock) in JsonText.clocks(row.str("field_clocks"))) {
            val kind = type.fields[name] ?: continue
            val c = HlcTimestamp.parse(clock.c) ?: continue
            fields[name] = FieldVersion(kind.toWire(row[name]), c, AuthorRank.fromWire(clock.u) ?: AuthorRank.AUTOMATIC)
        }
        return SyncRecord(
            id = row.id("id")!!, type = type.name, schema = row.int("schema") ?: 1, owner = type.ownerColumn?.let(row::id),
            deleted = (row.long("deleted") ?: 0L) != 0L, mergedInto = row.id("merged_into"), fields = fields,
        )
    }

    /** Writes the whole synced state of `record` (local columns untouched), then its row-local derived columns. */
    suspend fun store(sql: Sql, type: RecordType, record: SyncRecord) {
        sql.exec("INSERT OR IGNORE INTO ${type.name} (id) VALUES (?)", record.id)
        val clocks = HashMap<String, FieldClock>()
        val extra = HashMap<String, FieldVersion<JsonElement>>()
        for ((name, f) in record.fields) {
            if (name in type.fields) clocks[name] = FieldClock(f.clock.toString(), f.rank.wire) else extra[name] = f
        }
        val columns = mutableListOf("field_clocks", "deleted", "merged_into", "extra", "schema")
        val values = mutableListOf<Any?>(
            JsonText.encodeClocks(clocks), record.deleted, record.mergedInto, if (extra.isEmpty()) null else JsonText.encodeExtra(extra),
            record.schema,
        )
        for (name in type.fieldNames) {
            columns.add(name)
            values.add(
                if (name == type.ownerColumn && name !in record.fields) record.owner
                else record.fields[name]?.let { type.fields.getValue(name).toDatabase(it.value) },
            )
        }
        sql.exec("UPDATE ${type.name} SET ${columns.joinToString(", ") { "$it = ?" }} WHERE id = ?", *values.toTypedArray(), record.id)
        Derived.rowLocal(sql, type, record.id)
    }
}

/** Derived local columns computed from the row itself: keys, folds, review day. */
internal object Derived {
    suspend fun rowLocal(sql: Sql, type: RecordType, id: ToriId) {
        suspend fun text(col: String) = sql.text("SELECT $col FROM ${type.name} WHERE id = ?", id)
        when (type.name) {
            "entry" -> text("text").let { sql.exec("UPDATE entry SET match_key = ?, text_fold = ? WHERE id = ?", it?.let(TextKey::matchKey), it?.let(TextKey::searchFold), id) }
            "sense" -> sql.exec(
                "UPDATE sense SET translation_fold = ?, definition_fold = ? WHERE id = ?",
                text("translation")?.let(TextKey::searchFold), text("definition")?.let(TextKey::searchFold), id,
            )
            "context" -> sql.exec("UPDATE context SET sentence_fold = ? WHERE id = ?", text("sentence")?.let(TextKey::searchFold), id)
            "source" -> sql.exec("UPDATE source SET url_key = ? WHERE id = ?", text("url")?.let(UrlKey::of), id)
            "tag" -> sql.exec("UPDATE tag SET name_key = ? WHERE id = ?", text("name")?.let(TextKey::tagKey), id)
            "review_log" -> {
                val row = sql.row("SELECT reviewed_at, utc_offset_min FROM review_log WHERE id = ?", id)
                val at = row?.long("reviewed_at")
                val off = row?.int("utc_offset_min")
                sql.exec("UPDATE review_log SET review_day = ? WHERE id = ?", if (at != null && off != null) DayModel.dayNumber(at, off) else null, id)
            }
        }
    }
}

internal fun String?.wire(): JsonElement = this?.let(::JsonPrimitive) ?: JsonNull
internal val ToriId.wire: JsonElement get() = JsonPrimitive(toString())
internal fun Long.wire(): JsonElement = JsonPrimitive(this)
internal fun Int.wire(): JsonElement = JsonPrimitive(this.toLong())
