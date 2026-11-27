package com.toriwords.store

import com.toriwords.core.AuthorRank
import com.toriwords.core.CardDirection
import com.toriwords.core.CardStage
import com.toriwords.core.SyncRecord
import com.toriwords.core.ToriId
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

data class TagRow(val id: ToriId, val name: String)

data class EntryDetail(
    val id: ToriId,
    val text: String,
    val ipa: String?,
    val note: String?,
    val status: EntryStatus,
    val needsCheck: Boolean,
    val createdAt: Long,
    val senses: List<Sense>,
    val contexts: List<Context>,
    val tags: List<TagRow>,
    val cards: List<Card>,
) {
    data class Sense(
        val id: ToriId,
        val translation: String?,
        val definition: String?,
        val partOfSpeech: String?,
        /** The translation was written by a user action (rank 1). */
        val translationByUser: Boolean,
        val translationSource: SenseSource?,
    )

    data class Context(
        val id: ToriId,
        val sentence: String?,
        val highlight: Highlight?,
        val sourceId: ToriId?,
        val sourceTitle: String?,
        val sourceUrl: String?,
        val capturedAt: Long,
    )

    data class Card(val id: ToriId, val direction: CardDirection, val stage: CardStage, val dueDay: Int?, val reps: Int)
}

private const val LIVE_ENTRY = "e.deleted = 0 AND e.merged_into IS NULL"
private const val LIVE_SENSE = "s.deleted = 0 AND s.merged_into IS NULL"
private const val SENSE_ORDER = "(s.entry_id <> s.canonical_entry_id), s.position, s.id"

/** The live canonical Entry (a merged ID resolves to its survivor; null when deleted). */
suspend fun StoreReader.entry(id: ToriId): EntryDetail? {
    val canonical = sql.id("SELECT canonical_id FROM entry WHERE id = ?", id) ?: return null
    val row = sql.row("SELECT e.* FROM entry e WHERE e.id = ? AND $LIVE_ENTRY", canonical) ?: return null
    val senses = sql.rows("SELECT s.* FROM sense s WHERE s.canonical_entry_id = ? AND $LIVE_SENSE ORDER BY $SENSE_ORDER", canonical).map { r ->
        EntryDetail.Sense(
            r.id("id")!!, r.str("translation"), r.str("definition"), r.str("part_of_speech"),
            JsonText.clocks(r.str("field_clocks"))["translation"]?.u == AuthorRank.USER.wire, SenseSource.fromWire(r.str("translation_src")),
        )
    }
    val contexts = sql.rows(
        """SELECT c.id, c.sentence, c.highlight_offset, c.highlight_length, c.captured_at, so.id AS source_id, so.title, so.url
        FROM context c LEFT JOIN source s0 ON s0.id = c.source_id LEFT JOIN source so ON so.id = s0.canonical_id AND so.deleted = 0
        WHERE c.canonical_entry_id = ? AND c.deleted = 0 AND c.merged_into IS NULL ORDER BY c.captured_at, c.id""",
        canonical,
    ).map { r ->
        val o = r.int("highlight_offset")
        val l = r.int("highlight_length")
        EntryDetail.Context(
            r.id("id")!!, r.str("sentence"), if (o != null && l != null) Highlight(o, l) else null, r.id("source_id"), r.str("title"),
            r.str("url"), r.long("captured_at") ?: 0,
        )
    }
    val cards = sql.rows("SELECT id, direction, stage, due_day, reps FROM card WHERE canonical_entry_id = ? AND id = canonical_card_id", canonical)
        .mapNotNull { r ->
            val d = CardDirection.fromWire(r.str("direction") ?: "") ?: return@mapNotNull null
            EntryDetail.Card(r.id("id")!!, d, CardStage.entries.firstOrNull { it.wire == r.str("stage") } ?: CardStage.NEW, r.int("due_day"), r.int("reps") ?: 0)
        }.sortedBy { it.direction }
    val status = if (row.str("status") == "excluded") {
        if (row.str("excluded_reason") == "paused") EntryStatus.PAUSED else EntryStatus.KNOWN
    } else {
        EntryStatus.ACTIVE
    }
    return EntryDetail(
        canonical, row.str("text") ?: "", row.str("ipa"), row.str("note"), status, row.long("needs_check") == 1L, row.long("created_at") ?: 0,
        senses, contexts, tags(canonical), cards,
    )
}

/** Live canonical Tags the Entry is a member of (OR of `present`), by tag key. */
suspend fun StoreReader.tags(of: ToriId): List<TagRow> = sql.rows(
    """SELECT t.id, t.name FROM tag t WHERE t.deleted = 0 AND t.merged_into IS NULL AND EXISTS
    (SELECT 1 FROM entry_tag et WHERE et.canonical_entry_id = ? AND et.canonical_tag_id = t.id AND et.present = 1)
    ORDER BY t.name_key, t.id""",
    of,
).map { TagRow(it.id("id")!!, it.str("name") ?: "") }

/** All live canonical Tags by tag key. */
suspend fun StoreReader.allTags(): List<TagRow> =
    sql.rows("SELECT id, name FROM tag WHERE deleted = 0 AND merged_into IS NULL ORDER BY name_key, id").map { TagRow(it.id("id")!!, it.str("name") ?: "") }

/** One synced record as an envelope (what a push would send), or null. */
suspend fun StoreReader.record(type: RecordType, id: ToriId): SyncRecord? = RecordIO.load(sql, type, id)

/** Every synced record, parents first: what another device would pull (snapshots, backup). */
suspend fun StoreReader.allRecords(): List<SyncRecord> =
    RecordType.ALL.flatMap { type -> sql.rows("SELECT * FROM ${type.name} ORDER BY id").map { RecordIO.envelope(type, it) } }

/**
 * Scenario word projection (`fixtures/sync`): `{text, note, ipa, status, needsCheck, translations, contexts, tags,
 * reviews, extra}`; null when the Entry is not live.
 */
suspend fun StoreReader.word(id: ToriId): Map<String, JsonElement>? {
    val d = entry(id) ?: return null
    val extra = JsonText.extra(sql.text("SELECT extra FROM entry WHERE id = ?", id)).mapValues { it.value.value }
    val reviews = sql.long(
        "SELECT COUNT(*) FROM review_log r JOIN card c ON c.id = r.canonical_card_id WHERE c.canonical_entry_id = ? AND r.deleted = 0", id,
    ) ?: 0L
    return mapOf(
        "text" to JsonPrimitive(d.text), "note" to d.note.wire(), "ipa" to d.ipa.wire(), "status" to JsonPrimitive(d.status.name.lowercase()),
        "needsCheck" to JsonPrimitive(d.needsCheck), "translations" to JsonArray(d.senses.mapNotNull { s -> s.translation?.let(::JsonPrimitive) }),
        "contexts" to JsonArray(d.contexts.mapNotNull { c -> c.sentence?.let(::JsonPrimitive) }),
        "tags" to JsonArray(d.tags.map { it.name }.sorted().map(::JsonPrimitive)), "reviews" to JsonPrimitive(reviews), "extra" to JsonObject(extra),
    )
}

/**
 * Synced and derived state of visible records (device-local columns excluded), for convergence checks. Children of a
 * deleted Entry are hidden (their purge timing may differ per device). BLOBs print as their last 6 hex digits.
 */
suspend fun StoreReader.dump(): List<String> {
    val local = setOf("is_this_device", "enrich_attempts")
    val out = ArrayList<String>()
    for (type in RecordType.ALL) {
        val owner = type.ownerColumn?.let { col ->
            " AND NOT EXISTS (SELECT 1 FROM entry e WHERE e.deleted = 1 AND e.id IN (t.$col, (SELECT canonical_id FROM entry x WHERE x.id = t.$col)))"
        } ?: ""
        for (row in sql.rows("SELECT * FROM ${type.name} t WHERE deleted = 0$owner ORDER BY id")) {
            val cols = row.values.keys.sorted().filter { it !in local }
            out.add(type.name + " " + cols.joinToString(" ") { "$it=${dumpText(row[it])}" })
        }
    }
    return out
}

private fun dumpText(v: Any?): String = when (v) {
    null -> "NULL"
    is ByteArray -> v.joinToString("") { "%02x".format(it) }.takeLast(6)
    else -> v.toString()
}

