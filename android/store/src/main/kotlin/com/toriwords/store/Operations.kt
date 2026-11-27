package com.toriwords.store

import com.toriwords.core.AuthorRank
import com.toriwords.core.CardState
import com.toriwords.core.DayModel
import com.toriwords.core.Fsrs
import com.toriwords.core.FsrsParameters
import com.toriwords.core.Rating
import com.toriwords.core.SourceKey
import com.toriwords.core.TextKey
import com.toriwords.core.ToriId
import com.toriwords.core.UrlKey
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive

/** Where a Sense value came from (`*_src` columns). */
enum class SenseSource(val wire: String) {
    USER("user"), WIKTIONARY("wiktionary"), MT_APPLE("mt_apple"), MT_MLKIT("mt_mlkit");

    companion object {
        fun fromWire(value: String?): SenseSource? = entries.firstOrNull { it.wire == value }
    }
}

data class NewSense(
    val translation: String?,
    val definition: String? = null,
    val partOfSpeech: String? = null,
    val source: SenseSource = SenseSource.USER,
    val dictVersion: String? = null,
    val dictHeadwordKey: String? = null,
    val dictSenseOrdinal: Int? = null,
) {
    internal val fields: Map<String, JsonElement>
        get() {
            val src = JsonPrimitive(source.wire)
            return mapOf(
                "translation" to translation.wire(), "definition" to definition.wire(), "part_of_speech" to partOfSpeech.wire(),
                "translation_src" to if (translation == null) JsonNull else src, "definition_src" to if (definition == null) JsonNull else src,
                "pos_src" to if (partOfSpeech == null) JsonNull else src, "dict_version" to dictVersion.wire(),
                "dict_headword_key" to dictHeadwordKey.wire(), "dict_sense_ordinal" to (dictSenseOrdinal?.wire() ?: JsonNull),
            )
        }
}

enum class EntryStatus { ACTIVE, KNOWN, PAUSED }

sealed interface KeyEditResult {
    data object Saved : KeyEditResult

    /** The new text collides with this live record; nothing was written (call again with `mergeIfDuplicate`). */
    data class Duplicate(val of: ToriId) : KeyEditResult
}

/** UTF-16 code units in the sentence. */
data class Highlight(val offset: Int, val length: Int)

/** Where a capture came from. */
data class SourceInput(val kind: Kind, val url: String? = null, val title: String? = null, val app: String? = null) {
    enum class Kind(val wire: String) { WEB("web"), APP("app"), OTHER("other"), SUGGESTED("suggested") }
}

sealed class StoreError(message: String) : Exception(message) {
    class NotFound(what: String) : StoreError("not found: $what")
}

// Entry

/** Edits the text. A match-key collision is a user-initiated merge: returns [KeyEditResult.Duplicate] unless confirmed. */
suspend fun ToriStore.setEntryText(id: ToriId, text: String, mergeIfDuplicate: Boolean = false): KeyEditResult = write { tx ->
    val pair = tx.sql.id("SELECT language_pair_id FROM entry WHERE id = ?", id)
    val other = tx.sql.id(
        "SELECT id FROM entry WHERE ${DuplicateMerge.LIVE} AND language_pair_id IS ? AND match_key = ? AND id <> ? ORDER BY id LIMIT 1",
        pair, TextKey.matchKey(text), id,
    )
    if (other != null && !mergeIfDuplicate) return@write KeyEditResult.Duplicate(other)
    tx.set(RecordType.ENTRY, id, mapOf("text" to JsonPrimitive(text), "updated_at" to tx.now.wire()), AuthorRank.USER)
    KeyEditResult.Saved
}

suspend fun ToriStore.setEntryNote(id: ToriId, note: String?) {
    write { tx -> tx.set(RecordType.ENTRY, id, mapOf("note" to note.wire(), "updated_at" to tx.now.wire()), AuthorRank.USER) }
}

suspend fun ToriStore.setEntryIpa(id: ToriId, ipa: String?, rank: AuthorRank = AuthorRank.USER) {
    write { tx -> tx.set(RecordType.ENTRY, id, mapOf("ipa" to ipa.wire()), rank) }
}

/** Exclude (Known / Pause) or resume; bulk in one transaction. */
suspend fun ToriStore.setStatus(ids: List<ToriId>, status: EntryStatus) {
    write { tx ->
        for (id in ids) {
            tx.set(
                RecordType.ENTRY, id,
                mapOf(
                    "status" to JsonPrimitive(if (status == EntryStatus.ACTIVE) "active" else "excluded"),
                    "excluded_reason" to if (status == EntryStatus.ACTIVE) JsonNull else JsonPrimitive(status.name.lowercase()),
                ),
                AuthorRank.USER,
            )
        }
    }
}

/** Writes the tombstones (after the Undo window); bulk in one transaction. */
suspend fun ToriStore.deleteEntries(ids: List<ToriId>) {
    write { tx -> for (id in ids) tx.delete(RecordType.ENTRY, id) }
}

/** Opening the Entry screen: `needs_check = 0`, rank 0, only if it is 1. */
suspend fun ToriStore.markChecked(id: ToriId) {
    write { tx -> clearNeedsCheck(tx, id) }
}

internal suspend fun clearNeedsCheck(tx: Tx, id: ToriId) {
    if (tx.sql.long("SELECT needs_check FROM entry WHERE id = ?", id) == 1L) {
        tx.set(RecordType.ENTRY, id, mapOf("needs_check" to JsonPrimitive(false)), AuthorRank.AUTOMATIC)
    }
}

// Sense

suspend fun ToriStore.addSense(entry: ToriId, sense: NewSense): ToriId = write { tx -> addSense(tx, entry, sense, tx.newId(), AuthorRank.USER) }

internal suspend fun addSense(tx: Tx, entry: ToriId, sense: NewSense, id: ToriId, rank: AuthorRank): ToriId {
    val last = tx.sql.row("SELECT MAX(position) AS p FROM sense WHERE canonical_entry_id = ? OR entry_id = ?", entry, entry)?.double("p") ?: 0.0
    val fields = sense.fields + mapOf("entry_id" to entry.wire, "position" to FieldKind.jsonNumber(last + 1))
    tx.set(RecordType.SENSE, id, fields, rank)
    if (!sense.translation.isNullOrEmpty()) {
        tx.set(RecordType.ENTRY, entry, mapOf("enrichment_status" to JsonPrimitive("done")), AuthorRank.AUTOMATIC)
    }
    return id
}

/** User edit of a meaning; the edited fields become provenance `user`. */
suspend fun ToriStore.editSense(id: ToriId, translation: String?, definition: String?, partOfSpeech: String?) {
    write { tx ->
        val user = JsonPrimitive("user")
        tx.set(
            RecordType.SENSE, id,
            mapOf(
                "translation" to translation.wire(), "definition" to definition.wire(), "part_of_speech" to partOfSpeech.wire(),
                "translation_src" to user, "definition_src" to user, "pos_src" to user,
            ),
            AuthorRank.USER,
        )
    }
}

// Context and Source

/** Adds a Context unless one with the same sentence key and canonical Source exists on the Entry. */
internal suspend fun addContext(tx: Tx, entry: ToriId, sentence: String?, highlight: Highlight?, sourceId: ToriId?, capturedAt: Long): ToriId? {
    if (sentence == null && sourceId == null) return null
    val key = TextKey.sentenceKey(sentence ?: "")
    val canonicalSource = sourceId?.let { tx.sql.id("SELECT canonical_id FROM source WHERE id = ?", it) ?: it }
    val existing = tx.sql.rows(
        """SELECT c.id, c.sentence, s.canonical_id AS source FROM context c LEFT JOIN source s ON s.id = c.source_id
        WHERE c.deleted = 0 AND c.merged_into IS NULL AND (c.canonical_entry_id = ? OR c.entry_id = ?)""",
        entry, entry,
    )
    existing.firstOrNull { TextKey.sentenceKey(it.str("sentence") ?: "") == key && it.id("source") == canonicalSource }?.let { return it.id("id") }
    val id = tx.newId()
    tx.set(
        RecordType.CONTEXT, id,
        mapOf(
            "entry_id" to entry.wire, "sentence" to sentence.wire(), "source_id" to (sourceId?.wire ?: JsonNull),
            "highlight_offset" to (highlight?.offset?.wire() ?: JsonNull), "highlight_length" to (highlight?.length?.wire() ?: JsonNull),
            "captured_at" to capturedAt.wire(),
        ),
        AuthorRank.USER,
    )
    return id
}

/** Reuses a live Source by URL (deterministic ID) or by kind + title key + app, else creates one. */
internal suspend fun source(tx: Tx, input: SourceInput): ToriId {
    val url = input.url
    if (!url.isNullOrEmpty()) {
        val id = ToriId.source(UrlKey.of(url))
        if (RecordIO.load(tx.sql, RecordType.SOURCE, id) == null) {
            tx.set(
                RecordType.SOURCE, id,
                mapOf("kind" to JsonPrimitive(input.kind.wire), "url" to JsonPrimitive(url), "title" to input.title.wire(), "app" to input.app.wire()),
                AuthorRank.USER,
            )
        }
        return tx.sql.id("SELECT canonical_id FROM source WHERE id = ?", id) ?: id
    }
    val key = SourceKey.of(input.title, input.app, input.kind == SourceInput.Kind.SUGGESTED)
    val rows = tx.sql.rows("SELECT id, kind, title, app FROM source WHERE ${DuplicateMerge.LIVE} AND url IS NULL ORDER BY id")
    rows.firstOrNull { SourceKey.of(it.str("title"), it.str("app"), it.str("kind") == "suggested") == key }?.let { return it.id("id")!! }
    val id = tx.newId()
    tx.set(
        RecordType.SOURCE, id,
        mapOf("kind" to JsonPrimitive(input.kind.wire), "url" to JsonNull, "title" to input.title.wire(), "app" to input.app.wire()),
        AuthorRank.USER,
    )
    return id
}

// Tags

/** Tag Entries by name (reuse by tag key, else create): `present = 1` on the canonical pair's EntryTag. */
suspend fun ToriStore.tag(entries: List<ToriId>, name: String) = tag(entries, listOf(name))

/** Bulk Tag: only adds; every name on every Entry in one transaction. */
suspend fun ToriStore.tag(entries: List<ToriId>, names: List<String>) {
    write { tx ->
        for (name in names) {
            val tag = tagId(tx, name)
            for (e in entries) setMembership(tx, e, tag, present = true)
        }
    }
}

/** Untag: `present = 0` on every EntryTag resolving to the pair. */
suspend fun ToriStore.untag(entry: ToriId, tag: ToriId) {
    write { tx -> setMembership(tx, entry, tag, present = false) }
}

internal suspend fun tagId(tx: Tx, name: String): ToriId {
    tx.sql.id("SELECT id FROM tag WHERE ${DuplicateMerge.LIVE} AND name_key = ? ORDER BY id LIMIT 1", TextKey.tagKey(name))?.let { return it }
    val id = tx.newId()
    tx.set(RecordType.TAG, id, mapOf("name" to JsonPrimitive(name)), AuthorRank.USER)
    return id
}

internal suspend fun setMembership(tx: Tx, entry: ToriId, tag: ToriId, present: Boolean) {
    val e = tx.sql.id("SELECT canonical_id FROM entry WHERE id = ?", entry) ?: entry
    val t = tx.sql.id("SELECT canonical_id FROM tag WHERE id = ?", tag) ?: tag
    if (present) {
        tx.set(
            RecordType.ENTRY_TAG, ToriId.entryTag(e, t),
            mapOf("entry_id" to e.wire, "tag_id" to t.wire, "present" to JsonPrimitive(true)), AuthorRank.USER,
        )
    } else {
        for (id in tx.sql.ids("SELECT id FROM entry_tag WHERE canonical_entry_id = ? AND canonical_tag_id = ?", e, t)) {
            tx.set(RecordType.ENTRY_TAG, id, mapOf("present" to JsonPrimitive(false)), AuthorRank.USER)
        }
    }
}

// Enrichment

/** Automatic fill of a pending Entry: Sense `v5(autosense:entry:0)`, `needs_check = 1`, `done`; all rank 0. */
suspend fun ToriStore.fillAutomaticSense(entry: ToriId, sense: NewSense) {
    write { tx ->
        addSense(tx, entry, sense, ToriId.autoSense(entry, 0), AuthorRank.AUTOMATIC)
        tx.set(RecordType.ENTRY, entry, mapOf("needs_check" to JsonPrimitive(true), "enrichment_status" to JsonPrimitive("done")), AuthorRank.AUTOMATIC)
    }
}

// Settings

suspend fun ToriStore.setNewWordsPerDay(n: Int) {
    write { tx -> tx.set(RecordType.SETTINGS, ToriId.settings, mapOf("new_words_per_day" to n.coerceIn(ToriStore.NEW_WORDS_PER_DAY_RANGE).wire()), AuthorRank.USER) }
}

/** A new parameter set triggers a full replay rebuild. */
suspend fun ToriStore.setSchedulerParameters(p: FsrsParameters, paramsId: String) {
    write { tx ->
        tx.set(
            RecordType.SETTINGS, ToriId.settings,
            mapOf(
                "fsrs_w" to JsonArray(p.w.map(FieldKind::jsonNumber)), "desired_retention" to FieldKind.jsonNumber(p.desiredRetention),
                "params_id" to JsonPrimitive(paramsId),
            ),
            AuthorRank.USER,
        )
    }
}

// Review

/**
 * Commits one answer: ReviewLog + scheduler step + `needs_check` clear + outbox, one transaction. `card` is a canonical Card
 * ID from the queue. The step is incremental when the log is the Card's newest.
 */
suspend fun ToriStore.commitAnswer(card: ToriId, rating: Rating, reviewedAt: Long, utcOffsetMin: Int, answerMs: Int?): ToriId = write { tx ->
    val sql = tx.sql
    val row = sql.row(
        "SELECT entry_id, canonical_entry_id, stability, difficulty, last_review_day, due_day, reps, lapses FROM card WHERE id = ?", card,
    ) ?: throw StoreError.NotFound("card $card")
    val id = tx.newId()
    val device = sql.id("SELECT id FROM device WHERE is_this_device = 1")
    val newest = !sql.bool(
        "SELECT EXISTS (SELECT 1 FROM review_log WHERE canonical_card_id = ? AND (reviewed_at > ? OR (reviewed_at = ? AND id > ?)))",
        card, reviewedAt, reviewedAt, id,
    )
    tx.set(
        RecordType.REVIEW_LOG, id,
        mapOf(
            "card_id" to card.wire, "owner_entry_id" to (row.id("entry_id")?.wire ?: JsonNull), "reviewed_at" to reviewedAt.wire(),
            "utc_offset_min" to utcOffsetMin.wire(), "rating" to rating.value.wire(),
            "answer_ms" to (answerMs?.let { minOf(it, 600_000).wire() } ?: JsonNull), "device_id" to (device?.wire ?: JsonNull),
        ),
        AuthorRank.USER,
    )
    if (newest) {
        val state = row.double("stability")?.let { s ->
            val last = sql.long(
                """SELECT rating FROM review_log WHERE canonical_card_id = ? AND rating IS NOT NULL AND id <> ?
                ORDER BY reviewed_at DESC, id DESC LIMIT 1""",
                card, id,
            )?.let { Rating.of(it.toInt()) } ?: Rating.REMEMBERED
            CardState(s, row.double("difficulty")!!, row.int("last_review_day")!!, row.int("due_day")!!, row.int("reps")!!, row.int("lapses")!!, last, null)
        }
        val (p, paramsId) = Replay.parameters(sql)
        Replay.writeCache(sql, card, Fsrs.step(state, card, DayModel.dayNumber(reviewedAt, utcOffsetMin), rating, p), paramsId)
        tx.stepped.add(card)
    }
    row.id("canonical_entry_id")?.let { clearNeedsCheck(tx, it) }
    id
}
