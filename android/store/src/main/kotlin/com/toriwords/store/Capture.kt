package com.toriwords.store

import com.toriwords.core.AuthorRank
import com.toriwords.core.TextKey
import com.toriwords.core.ToriId
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive

/** One capture (Add screen, capture sheet). */
data class CaptureInput(
    val term: String,
    val capturedAt: Long,
    /** `typed` / `shared` / `text_selection` / `imported`. */
    val origin: String = "typed",
    val nativeLang: String = "ru",
    val targetLang: String = "en",
    val senses: List<NewSense> = emptyList(),
    val sentence: String? = null,
    val highlight: Highlight? = null,
    val source: SourceInput? = null,
    val tags: List<String> = emptyList(),
    val resume: Boolean = false,
)

/** Runs a capture; returns the (possibly existing) Entry ID. */
suspend fun ToriStore.capture(input: CaptureInput): ToriId = write { tx -> capture(tx, input) }

internal suspend fun capture(tx: Tx, input: CaptureInput): ToriId {
    val sql = tx.sql
    val pair = ToriId.languagePair(input.nativeLang, input.targetLang)
    val existing = sql.id(
        "SELECT id FROM entry WHERE ${DuplicateMerge.LIVE} AND language_pair_id = ? AND match_key = ? ORDER BY id LIMIT 1",
        pair, TextKey.matchKey(input.term),
    )
    val entry: ToriId
    if (existing != null) {
        entry = existing
        if (input.resume && sql.text("SELECT status FROM entry WHERE id = ?", entry) == "excluded") {
            tx.set(RecordType.ENTRY, entry, mapOf("status" to JsonPrimitive("active"), "excluded_reason" to JsonNull), AuthorRank.USER)
        }
    } else {
        entry = tx.newId()
        tx.set(
            RecordType.ENTRY, entry,
            mapOf(
                "language_pair_id" to pair.wire, "text" to JsonPrimitive(input.term), "status" to JsonPrimitive("active"),
                "origin" to JsonPrimitive(input.origin), "created_at" to input.capturedAt.wire(), "updated_at" to tx.now.wire(),
            ),
            AuthorRank.USER,
        )
        tx.set(RecordType.ENTRY, entry, mapOf("needs_check" to JsonPrimitive(false), "enrichment_status" to JsonPrimitive("pending")), AuthorRank.AUTOMATIC)
    }

    val seen = sql.rows(
        "SELECT translation FROM sense WHERE ${DuplicateMerge.LIVE} AND (canonical_entry_id = ? OR entry_id = ?) AND translation IS NOT NULL",
        entry, entry,
    ).map { TextKey.translationKey(it.str("translation")!!) }.toMutableSet()
    for (sense in input.senses) {
        val key = TextKey.translationKey(sense.translation ?: "")
        if (key.isNotEmpty() && !seen.add(key)) continue
        addSense(tx, entry, sense, tx.newId(), AuthorRank.USER)
    }

    val sourceId = input.source?.let { source(tx, it) }
    addContext(tx, entry, input.sentence, input.highlight, sourceId, input.capturedAt)
    for (name in input.tags) if (TextKey.tagKey(name).isNotEmpty()) setMembership(tx, entry, tagId(tx, name), present = true)
    val hasTranslation = sql.bool(
        "SELECT EXISTS (SELECT 1 FROM sense WHERE ${DuplicateMerge.LIVE} AND (canonical_entry_id = ? OR entry_id = ?) AND translation <> '')",
        entry, entry,
    )
    if (!hasTranslation) tx.set(RecordType.ENTRY, entry, mapOf("enrichment_status" to JsonPrimitive("pending")), AuthorRank.AUTOMATIC)
    return entry
}
