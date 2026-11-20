package com.toriwords.store

import com.toriwords.core.AuthorRank
import com.toriwords.core.CardDirection
import com.toriwords.core.CardStage
import com.toriwords.core.CardState
import com.toriwords.core.Fsrs
import com.toriwords.core.FsrsParameters
import com.toriwords.core.Rating
import com.toriwords.core.ReviewLogInput
import com.toriwords.core.SourceKey
import com.toriwords.core.SyncRecord
import com.toriwords.core.TextKey
import com.toriwords.core.ToriId
import com.toriwords.store.Sql.Companion.idArgs
import com.toriwords.store.Sql.Companion.ph
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.double

/** Canonical-ID resolution and child re-linking. */
internal object Canonical {
    private val MERGEABLE = listOf(RecordType.ENTRY, RecordType.SENSE, RecordType.CONTEXT, RecordType.TAG, RecordType.SOURCE)

    suspend fun resolve(tx: Tx) {
        val sql = tx.sql
        val changed = HashMap<String, MutableSet<ToriId>>()
        for (type in MERGEABLE) {
            val touched = tx.touched(type)
            if (touched.isEmpty()) continue
            val into = HashMap<ToriId, ToriId>()
            for (row in sql.rows("SELECT id, merged_into FROM ${type.name} WHERE merged_into IS NOT NULL")) into[row.id("id")!!] = row.id("merged_into")!!
            fun end(id: ToriId): ToriId {
                var cur = id
                repeat(64) { cur = into[cur] ?: return cur }
                return cur
            }
            val check = touched + into.keys
            for (row in sql.rows("SELECT id, canonical_id FROM ${type.name} WHERE id IN ${ph(check.size)}", idArgs(check))) {
                val id = row.id("id")!!
                val target = end(id)
                if (row.id("canonical_id") != target) {
                    sql.exec("UPDATE ${type.name} SET canonical_id = ? WHERE id = ?", target, id)
                    changed.getOrPut(type.name) { HashSet() }.add(id)
                }
            }
        }

        val entries = tx.touched(RecordType.ENTRY) + (changed["entry"] ?: emptySet())
        for (child in listOf("sense", "context", "card", "entry_tag")) {
            val own = tx.touched(child)
            if (entries.isEmpty() && own.isEmpty()) continue
            sql.exec(
                """UPDATE $child SET canonical_entry_id = (SELECT canonical_id FROM entry WHERE entry.id = $child.entry_id)
                WHERE entry_id IN ${ph(entries.size)} OR id IN ${ph(own.size)}""",
                idArgs(entries), idArgs(own),
            )
        }

        val tags = tx.touched(RecordType.TAG) + (changed["tag"] ?: emptySet())
        val links = tx.touched(RecordType.ENTRY_TAG)
        if (tags.isNotEmpty() || links.isNotEmpty()) {
            sql.exec(
                """UPDATE entry_tag SET canonical_tag_id = (SELECT canonical_id FROM tag WHERE tag.id = entry_tag.tag_id)
                WHERE tag_id IN ${ph(tags.size)} OR id IN ${ph(links.size)}""",
                idArgs(tags), idArgs(links),
            )
        }

        // Cards: canonical Card = v5(card:canonicalEntry:direction); every change replays old and new.
        val touchedCards = tx.touched(RecordType.CARD)
        val relinked = HashSet(touchedCards)
        if (entries.isNotEmpty() || touchedCards.isNotEmpty()) {
            val rows = sql.rows(
                """SELECT id, direction, canonical_entry_id, canonical_card_id FROM card
                WHERE entry_id IN ${ph(entries.size)} OR id IN ${ph(touchedCards.size)}""",
                idArgs(entries), idArgs(touchedCards),
            )
            for (row in rows) {
                val id = row.id("id")!!
                val old = row.id("canonical_card_id")
                val direction = CardDirection.fromWire(row.str("direction") ?: "")
                val new = row.id("canonical_entry_id")?.let { e -> direction?.let { ToriId.card(e, it) } }
                if (new != null) tx.replay.add(new)
                if (old != new) {
                    sql.exec("UPDATE card SET canonical_card_id = ? WHERE id = ?", new, id)
                    if (old != null) tx.replay.add(old)
                    relinked.add(id)
                }
            }
        }
        val logs = tx.touched(RecordType.REVIEW_LOG)
        if (relinked.isNotEmpty() || logs.isNotEmpty()) {
            sql.exec(
                """UPDATE review_log SET canonical_card_id = (SELECT canonical_card_id FROM card WHERE card.id = review_log.card_id)
                WHERE card_id IN ${ph(relinked.size)} OR id IN ${ph(logs.size)}""",
                idArgs(relinked), idArgs(logs),
            )
            if (logs.isNotEmpty()) {
                tx.replay.addAll(
                    sql.ids(
                        "SELECT DISTINCT canonical_card_id FROM review_log WHERE canonical_card_id IS NOT NULL AND id IN ${ph(logs.size)}",
                        idArgs(logs),
                    ),
                )
            }
        }
    }

    /** A merge group is deleted when any member carries a tombstone: write it on the live survivor. */
    suspend fun propagateTombstones(tx: Tx) {
        for (type in MERGEABLE) {
            if (tx.touched(type).isEmpty()) continue
            val survivors = tx.sql.ids(
                """SELECT DISTINCT canonical_id FROM ${type.name} t WHERE deleted = 1 AND merged_into IS NOT NULL
                AND EXISTS (SELECT 1 FROM ${type.name} s WHERE s.id = t.canonical_id AND s.deleted = 0)""",
            )
            for (id in survivors) tx.delete(type, id)
        }
        // A deleted Entry group: its other Entries become value-less tombstones too (the cloud keeps no values of the group).
        if (tx.touched(RecordType.ENTRY).isEmpty()) return
        for (id in tx.sql.ids("SELECT m.id FROM entry m JOIN entry c ON c.id = m.canonical_id WHERE m.deleted = 0 AND m.id != c.id AND c.deleted = 1")) {
            tx.delete(RecordType.ENTRY, id)
        }
    }
}

/** Deterministic duplicate merge (doc 36 §11.7). [run] returns whether anything merged (the caller repeats until stable). */
internal object DuplicateMerge {
    const val LIVE = "deleted = 0 AND merged_into IS NULL"

    suspend fun run(tx: Tx): Boolean {
        var merged = false
        val sql = tx.sql
        val touchedEntries = tx.touched(RecordType.ENTRY)

        // Entries: canonical LanguagePair + match key.
        val keys = sql.rows(
            "SELECT DISTINCT language_pair_id, match_key FROM entry WHERE $LIVE AND match_key IS NOT NULL AND id IN ${ph(touchedEntries.size)}",
            idArgs(touchedEntries),
        )
        for (k in keys) {
            val ids = sql.ids("SELECT id FROM entry WHERE $LIVE AND language_pair_id IS ? AND match_key = ? ORDER BY id", k["language_pair_id"], k.str("match_key"))
            merged = merge(tx, RecordType.ENTRY, ids) || merged
        }

        // Children of affected canonical Entries.
        for (e in affectedEntries(tx)) {
            val senses = sql.rows("SELECT id, translation, definition FROM sense WHERE $LIVE AND canonical_entry_id = ? ORDER BY id", e)
            merged = mergeGroups(tx, RecordType.SENSE, senses) { row ->
                val t = TextKey.matchKey(row.str("translation") ?: "")
                if (t.isNotEmpty()) "t:$t" else TextKey.matchKey(row.str("definition") ?: "").takeIf { it.isNotEmpty() }?.let { "d:$it" }
            } || merged
            val contexts = sql.rows(
                """SELECT c.id, c.sentence, c.source_id, s.canonical_id AS source FROM context c LEFT JOIN source s ON s.id = c.source_id
                WHERE c.deleted = 0 AND c.merged_into IS NULL AND c.canonical_entry_id = ? ORDER BY c.id""",
                e,
            )
            merged = mergeGroups(tx, RecordType.CONTEXT, contexts) { row ->
                TextKey.sentenceKey(row.str("sentence") ?: "") + "|" + (row.id("source") ?: row.id("source_id") ?: "-")
            } || merged
        }

        // Tags: tag key.
        val touchedTags = tx.touched(RecordType.TAG)
        if (touchedTags.isNotEmpty()) {
            val tags = sql.rows(
                "SELECT id, name_key FROM tag WHERE $LIVE AND name_key IN (SELECT name_key FROM tag WHERE id IN ${ph(touchedTags.size)}) ORDER BY id",
                idArgs(touchedTags),
            )
            merged = mergeGroups(tx, RecordType.TAG, tags) { it.str("name_key") } || merged
        }

        // Sources without URL: title match key + app (+ kind when suggested).
        if (tx.touched(RecordType.SOURCE).isNotEmpty()) {
            val sources = sql.rows("SELECT id, kind, title, app FROM source WHERE $LIVE AND url IS NULL ORDER BY id")
            merged = mergeGroups(tx, RecordType.SOURCE, sources) { row ->
                val k = SourceKey.of(row.str("title"), row.str("app"), row.str("kind") == "suggested")
                "${k.title}\u0000${k.app ?: ""}\u0000${k.suggested}"
            } || merged
        }
        return merged
    }

    /** Canonical Entries whose children may hold new duplicates. */
    suspend fun affectedEntries(tx: Tx): Set<ToriId> {
        val sql = tx.sql
        val result = LinkedHashSet<ToriId>()
        val entries = tx.touched(RecordType.ENTRY)
        result.addAll(sql.ids("SELECT canonical_id FROM entry WHERE id IN ${ph(entries.size)}", idArgs(entries)))
        for (child in listOf("sense", "context")) {
            val ids = tx.touched(child)
            result.addAll(sql.ids("SELECT canonical_entry_id FROM $child WHERE canonical_entry_id IS NOT NULL AND id IN ${ph(ids.size)}", idArgs(ids)))
        }
        val sources = tx.touched(RecordType.SOURCE)
        result.addAll(
            sql.ids("SELECT canonical_entry_id FROM context WHERE canonical_entry_id IS NOT NULL AND source_id IN ${ph(sources.size)}", idArgs(sources)),
        )
        return result
    }

    /** Rows must be ordered by ID; null key = never merged. */
    private suspend fun mergeGroups(tx: Tx, type: RecordType, rows: List<Row>, key: (Row) -> String?): Boolean {
        val groups = LinkedHashMap<String, MutableList<ToriId>>()
        for (row in rows) key(row)?.let { groups.getOrPut(it) { ArrayList() }.add(row.id("id")!!) }
        var merged = false
        for (ids in groups.values) merged = merge(tx, type, ids) || merged
        return merged
    }

    /** Survivor = smallest ID; losers get `merged_into` (rank 0, outbox) and the survivor takes their winning fields. */
    private suspend fun merge(tx: Tx, type: RecordType, ids: List<ToriId>): Boolean {
        if (ids.size < 2) return false
        val survivor = ids.min()
        for (loser in ids) {
            if (loser == survivor) continue
            val record = RecordIO.load(tx.sql, type, loser)?.copy(mergedInto = survivor) ?: continue
            tx.storeLocal(type, record)
            tx.outbox(type, loser, "_mergedInto", tx.stamp())
            absorb(tx, type, record, survivor)
        }
        return true
    }

    /** Field merge into the survivor: original clocks and ranks copied, no outbox. The owner never changes. */
    suspend fun absorb(tx: Tx, type: RecordType, loser: SyncRecord, survivorId: ToriId) {
        val survivor = RecordIO.load(tx.sql, type, survivorId) ?: return
        if (survivor.deleted) return
        val fields = LinkedHashMap(survivor.fields)
        var changed = false
        for ((name, f) in loser.fields) {
            if (name == type.ownerColumn) continue
            val s = fields[name]
            if (s != null && !f.winsOver(s)) continue
            fields[name] = f
            changed = true
        }
        if (changed) tx.storeLocal(type, survivor.copy(fields = fields))
    }
}

/** Card creation for Entries that became reviewable, rank 0, deterministic IDs. */
internal object Cards {
    suspend fun createMissing(tx: Tx) {
        val sql = tx.sql
        for (e in DuplicateMerge.affectedEntries(tx)) {
            val reviewable = sql.bool(
                """SELECT EXISTS (SELECT 1 FROM entry WHERE id = ? AND ${DuplicateMerge.LIVE} AND status = 'active')
                AND EXISTS (SELECT 1 FROM sense WHERE canonical_entry_id = ? AND ${DuplicateMerge.LIVE} AND translation <> '')""",
                e, e,
            )
            if (!reviewable) continue
            val directions = mutableListOf(CardDirection.RECOGNITION, CardDirection.RECALL)
            val cloze = sql.bool(
                """SELECT EXISTS (SELECT 1 FROM context WHERE canonical_entry_id = ? AND ${DuplicateMerge.LIVE}
                AND sentence IS NOT NULL AND highlight_offset IS NOT NULL)""",
                e,
            )
            if (cloze) directions.add(CardDirection.CLOZE)
            for (d in directions) {
                val id = ToriId.card(e, d)
                if (sql.bool("SELECT EXISTS (SELECT 1 FROM card WHERE id = ?)", id)) continue
                tx.set(
                    RecordType.CARD, id,
                    mapOf("entry_id" to e.wire, "direction" to JsonPrimitive(d.wire), "created_at" to tx.now.wire()), AuthorRank.AUTOMATIC,
                )
            }
        }
    }
}

/** Card cache = replay of its canonical logs (doc 36 §7.6). */
internal object Replay {
    const val DEFAULT_PARAMS_ID = "fsrs6-default-1"

    suspend fun parameters(sql: Sql): Pair<FsrsParameters, String> {
        val row = sql.row("SELECT fsrs_w, desired_retention, params_id FROM settings WHERE id = ?", ToriId.settings)
        val default = FsrsParameters.DEFAULT
        val w = row?.str("fsrs_w")?.let { text ->
            runCatching { JsonText.json.parseToJsonElement(text).jsonArray.map { it.jsonPrimitive.double } }.getOrNull()
        } ?: default.w
        val retention = row?.double("desired_retention") ?: default.desiredRetention
        val p = if (w.size == default.w.size) FsrsParameters(w, retention) else default
        return p to (row?.str("params_id") ?: DEFAULT_PARAMS_ID)
    }

    suspend fun run(tx: Tx) {
        val sql = tx.sql
        val cards = if (tx.paramsChanged) sql.ids("SELECT id FROM card WHERE id = canonical_card_id").toSet() else tx.replay - tx.stepped
        if (cards.isEmpty()) return
        val (p, paramsId) = parameters(sql)
        for (id in cards) {
            // A merged-away card has no cache, however it got here (merged locally or pulled already merged).
            val canonical = sql.id("SELECT canonical_card_id FROM card WHERE id = ?", id)
            if (canonical != null && canonical != id) {
                sql.exec(
                    """UPDATE card SET stability = NULL, difficulty = NULL, last_review_day = NULL, due_day = NULL, reps = NULL,
                    lapses = NULL, stage = NULL, params_id = NULL WHERE id = ?""",
                    id,
                )
                continue
            }
            val logs = sql.rows("SELECT id, reviewed_at, utc_offset_min, rating FROM review_log WHERE canonical_card_id = ? AND reviewed_at IS NOT NULL", id)
                .map { r -> ReviewLogInput(r.id("id")!!, id, r.long("reviewed_at")!!, r.int("utc_offset_min") ?: 0, r.int("rating")?.let(Rating::of)) }
            writeCache(sql, id, Fsrs.replay(id, logs, p), paramsId)
        }
        tx.replay.clear()
    }

    suspend fun writeCache(sql: Sql, id: ToriId, s: CardState?, paramsId: String) {
        sql.exec(
            "UPDATE card SET stability = ?, difficulty = ?, last_review_day = ?, due_day = ?, reps = ?, lapses = ?, stage = ?, params_id = ? WHERE id = ?",
            s?.stability, s?.difficulty, s?.lastReviewDay, s?.dueDay, s?.reps ?: 0, s?.lapses ?: 0, (s?.stage ?: CardStage.NEW).wire, paramsId, id,
        )
    }
}

/** Explicit purge of a deleted Entry's children; no cascades (doc 36 §4.3). */
internal object Purge {
    private val CHILDREN = listOf("sense", "context", "card", "entry_tag")

    /**
     * Deletes the children of deleted Entries' groups (tombstones stay). `queueCloudDeletes` (sync active): the purged
     * children's outbox rows go, and every Entry of the group is queued as a Drive purge owner (`_cloudDelete`): the Drive
     * purge rewrites files by owner (doc 38 §11.2 Purge), so the owners are what the engine needs.
     */
    suspend fun deletedEntries(sql: Sql, among: Set<ToriId>, queueCloudDeletes: Boolean = false) {
        val deleted = sql.ids(
            """SELECT id FROM entry WHERE deleted = 1 AND id IN ${ph(among.size)}
            AND NOT EXISTS (SELECT 1 FROM pending_changes WHERE record_id = entry.id AND field = '_deleted')""",
            idArgs(among),
        )
        if (deleted.isEmpty()) return
        val group = deleted.toSet() + sql.ids("SELECT id FROM entry WHERE canonical_id IN ${ph(deleted.size)}", idArgs(deleted))
        val p = ph(group.size)
        val owned = CHILDREN.map { it to "entry_id IN $p OR canonical_entry_id IN $p" } + ("review_log" to "owner_entry_id IN $p")
        for ((table, condition) in owned) {
            val args = if (table == "review_log") listOf(idArgs(group)) else listOf(idArgs(group), idArgs(group))
            if (queueCloudDeletes) {
                for (id in sql.ids("SELECT id FROM $table WHERE $condition", *args.toTypedArray())) Outbox.dropPending(sql, id)
            }
            sql.exec("DELETE FROM $table WHERE $condition", *args.toTypedArray())
        }
        if (queueCloudDeletes) for (entry in group) Outbox.queueCloudDelete(sql, entry)
    }

    /** Records the cloud deleted: only hidden children (owner Entry deleted) are purged here; anything else stays. */
    suspend fun hiddenChildren(sql: Sql, ids: List<ToriId>) {
        if (ids.isEmpty()) return
        for (type in RecordType.ALL) {
            val owner = type.ownerColumn ?: continue
            sql.exec(
                """DELETE FROM ${type.name} WHERE id IN ${ph(ids.size)} AND EXISTS (SELECT 1 FROM entry e LEFT JOIN entry c ON c.id = e.canonical_id
                WHERE e.id = ${type.name}.$owner AND (e.deleted = 1 OR c.deleted = 1))""",
                idArgs(ids),
            )
        }
    }
}
