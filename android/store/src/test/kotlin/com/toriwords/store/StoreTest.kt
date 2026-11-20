package com.toriwords.store

import com.toriwords.core.AuthorRank
import com.toriwords.core.CardDirection
import com.toriwords.core.FieldVersion
import com.toriwords.core.Fsrs
import com.toriwords.core.FsrsParameters
import com.toriwords.core.HlcState
import com.toriwords.core.HlcTimestamp
import com.toriwords.core.Rating
import com.toriwords.core.ReviewLogInput
import com.toriwords.core.SyncRecord
import com.toriwords.core.ToriId
import com.toriwords.core.WireJson
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class StoreTest {

    @Test fun schemaAndPragmas() = runBlocking {
        val s = TestStore(launch = false, file = true)
        assertEquals(1L, s.long("SELECT version FROM schema_meta"))
        assertEquals("wal", s.text("PRAGMA journal_mode"))
        assertEquals(1L, s.long("PRAGMA synchronous"))
        assertEquals("UTF-8", s.text("PRAGMA encoding"))
        assertEquals(1L, s.long("SELECT sqlite_compileoption_used('ENABLE_FTS5')"))
        val tables = s.rows("SELECT name FROM sqlite_master WHERE type = 'table'").map { it.str("name")!! }.toSet()
        assertTrue(tables.containsAll(RecordType.ALL.map { it.name } + listOf("pending_changes", "sync_state", "inbox_import", "schema_meta", "drive_file", "drive_file_owner")))
        assertFalse("no CloudKit meta on Android", "cloud_record_meta" in tables)
        // BINARY collation and unsigned BLOB order.
        assertEquals("B", s.text("SELECT x FROM (SELECT 'a' AS x UNION SELECT 'B') ORDER BY x LIMIT 1"))
        s.store.close()
    }

    @Test fun launchFreshThenRestore() = runBlocking {
        val s = TestStore(launch = false)
        assertEquals(LaunchOutcome.FRESH_INSTALL, s.store.launch(s.marker, "Pixel"))
        val first = s.store.thisDeviceId()!!
        assertEquals(first, ToriId.fromBytes(s.marker.readBytes()))
        assertEquals(10L, s.long("SELECT new_words_per_day FROM settings WHERE id = ?", ToriId.settings))
        assertEquals("ru", s.text("SELECT native_lang FROM language_pair WHERE id = ?", ToriId.languagePair("ru", "en")))
        assertEquals("android", s.text("SELECT platform FROM device WHERE id = ?", first))
        assertTrue(s.text("SELECT field_clocks FROM settings")!!.contains("\"u\":0"))
        assertEquals(LaunchOutcome.EXISTING, s.store.launch(s.marker, "Pixel"))

        // Restored from a backup: the marker (no-backup dir) is missing; token and file index are stale.
        s.activate()
        val e = s.store.capture(CaptureInput("run", T0))
        s.store.applyCloudChanges(emptyList(), token = "tok", index = listOf(DriveFileIndex(file("f1"), emptyList())))
        s.store.recordSaved(s.store.pendingPush().rows)
        s.marker.delete()
        assertEquals(LaunchOutcome.RESTORED_FROM_BACKUP, s.store.launch(s.marker, "Pixel"))
        val second = s.store.thisDeviceId()!!
        assertNotEquals(first, second)
        assertEquals(0L, s.long("SELECT is_this_device FROM device WHERE id = ?", first))
        assertNull(s.store.syncState(SyncStateKey.PAGE_TOKEN))
        assertEquals(0L, s.long("SELECT COUNT(*) FROM drive_file"))
        assertEquals("account-1", s.store.syncState(SyncStateKey.DRIVE_ACCOUNT))
        assertTrue(s.store.pendingPush().records.any { it.id == e })
    }

    @Test fun outboxOnlyWhileDriveActiveAndNotDeleted() = runBlocking {
        val s = TestStore()
        val a = s.store.capture(CaptureInput("run", T0, senses = listOf(tr("бежать"))))
        assertEquals(0, s.store.pendingRecordCount())
        val clocks = JsonText.clocks(s.text("SELECT field_clocks FROM entry WHERE id = ?", a))
        assertEquals(1, clocks["text"]?.u)
        assertEquals(0, clocks["enrichment_status"]?.u)
        assertEquals(0, clocks["needs_check"]?.u)

        s.activate()
        s.store.recordSaved(s.store.pendingPush(maxRecords = 1000).rows)
        assertEquals(0, s.store.pendingRecordCount())
        s.ms += 1
        s.store.setEntryNote(a, "note")
        assertEquals(setOf("entry.note", "entry.updated_at"), s.rows("SELECT type, field FROM pending_changes").map { "${it.str("type")}.${it.str("field")}" }.toSet())
        val push = s.store.pendingPush()
        assertEquals(1, push.records.size)
        assertTrue("full envelope", "text" in push.records[0].fields)

        // Ack removes only rows whose clock is unchanged.
        s.ms += 1
        s.store.setEntryNote(a, "newer")
        s.store.recordSaved(push.rows)
        assertEquals(listOf("note", "updated_at"), s.rows("SELECT field FROM pending_changes").map { it.str("field")!! }.sorted())
        s.store.recordSaved(s.store.pendingPush().rows)
        assertEquals(0, s.store.pendingRecordCount())

        // A caller limit bounds the batch.
        s.store.markAllPending()
        assertEquals(2, s.store.pendingPush(maxRecords = 2).records.size)

        // Drive data deleted: no outbox rows, clocks still stamped, index gone.
        s.store.applyCloudChanges(emptyList(), token = "t", index = listOf(DriveFileIndex(file("f1"), emptyList())))
        s.store.markDriveDeleted()
        assertFalse(s.store.isOutboxActive())
        s.store.setEntryNote(a, "local edit")
        assertEquals(0, s.store.pendingRecordCount())
        assertEquals("local edit", s.text("SELECT note FROM entry WHERE id = ?", a))
        assertEquals(0L, s.long("SELECT COUNT(*) FROM drive_file"))

        // Back up this device again: active, everything pending.
        s.store.backUpAgain()
        assertTrue(s.store.isOutboxActive())
        assertTrue(s.store.pendingRecordCount() > 0)
    }

    @Test fun automaticWriteNeverOverridesUserValue() = runBlocking {
        val s = TestStore()
        val e = s.store.capture(CaptureInput("run", T0))
        s.store.fillAutomaticSense(e, tr("бежать"))
        val auto = ToriId.autoSense(e, 0)
        s.store.editSense(auto, "", null, null)
        s.store.fillAutomaticSense(e, tr("бегать"))
        assertEquals("", s.text("SELECT translation FROM sense WHERE id = ?", auto))
    }

    @Test fun clockAheadRecoveryRestampsPendingFields() = runBlocking {
        val s = TestStore()
        s.activate()
        s.ms = T0 + 10 * HlcState.HOUR_MS
        val e = s.store.capture(CaptureInput("run", T0))
        s.ms = T0
        assertTrue(s.store.recoverClockAhead(T0))
        assertTrue(s.rows("SELECT clock FROM pending_changes").all { HlcTimestamp.parse(it.str("clock")!!)!!.ms == T0 })
        assertTrue(JsonText.clocks(s.text("SELECT field_clocks FROM entry WHERE id = ?", e)).values.all { HlcTimestamp.parse(it.c)!!.ms == T0 })
        assertFalse(s.store.recoverClockAhead(T0))
    }

    @Test fun mergeByEditIsAskedThenDeterministic() = runBlocking {
        val s = TestStore()
        s.activate()
        val run = s.store.capture(CaptureInput("run", T0, senses = listOf(tr("бежать"))))
        s.ms += 1000
        val walk = s.store.capture(CaptureInput("walk", T0, senses = listOf(tr("идти"))))
        assertEquals(KeyEditResult.Duplicate(run), s.store.setEntryText(walk, "Run"))
        assertEquals("walk", s.text("SELECT text FROM entry WHERE id = ?", walk))

        assertEquals(KeyEditResult.Saved, s.store.setEntryText(walk, "Run", mergeIfDuplicate = true))
        val survivor = minOf(run, walk)
        val loser = maxOf(run, walk)
        assertEquals(survivor, s.store.read { it.sql.id("SELECT merged_into FROM entry WHERE id = ?", loser) })
        assertEquals(1L, s.long("SELECT COUNT(*) FROM pending_changes WHERE record_id = ? AND field = '_mergedInto'", loser))
        val detail = s.store.read { it.entry(loser) }!!
        assertEquals(survivor, detail.id)
        assertEquals(listOf("бежать", "идти"), detail.senses.map { it.translation })
        assertEquals("Run", detail.text)
        assertEquals(setOf(ToriId.card(survivor, CardDirection.RECOGNITION), ToriId.card(survivor, CardDirection.RECALL)), detail.cards.map { it.id }.toSet())
    }

    @Test fun postPullMergePicksSmallestIdAndKeepsHistory() = runBlocking {
        val phone = TestStore(now = T0 + 60_000)
        val tablet = TestStore(now = T0)
        val mine = phone.store.capture(CaptureInput("take off", T0, senses = listOf(tr("взлетать"))))
        val theirs = tablet.store.capture(CaptureInput("Take  off", T0, senses = listOf(tr("снимать"))))
        assertTrue(theirs < mine)
        phone.store.commitAnswer(ToriId.card(mine, CardDirection.RECOGNITION), Rating.REMEMBERED, T0 + 120_000, 0, 1000)

        phone.store.applyCloudChanges(tablet.records(), token = "1")
        assertEquals(theirs, phone.store.read { it.sql.id("SELECT merged_into FROM entry WHERE id = ?", mine) })
        assertEquals("1", phone.store.syncState(SyncStateKey.PAGE_TOKEN))
        val detail = phone.store.read { it.entry(mine) }!!
        assertEquals(theirs, detail.id)
        assertEquals(setOf("взлетать", "снимать"), detail.senses.mapNotNull { it.translation }.toSet())
        assertEquals(1, detail.cards.first { it.direction == CardDirection.RECOGNITION }.reps)
        assertEquals(ToriId.card(theirs, CardDirection.RECOGNITION), phone.store.read { it.sql.id("SELECT canonical_card_id FROM review_log") })
    }

    @Test fun tagsMergeByKeyAndMembershipIsOr() = runBlocking {
        val a = TestStore(now = T0)
        val b = TestStore(now = T0 + 1000)
        val e = a.store.capture(CaptureInput("run", T0, tags = listOf("Work")))
        b.store.applyCloudChanges(a.records())
        val f = b.store.capture(CaptureInput("walk", T0))
        // A second "work" Tag created elsewhere merges by tag key on pull.
        val c = TestStore(now = T0 + 2000)
        c.store.applyCloudChanges(b.records())
        c.store.tag(listOf(f), "WORK")
        b.store.applyCloudChanges(c.records())
        val tags = b.store.read { it.allTags() }
        assertEquals(listOf("Work"), tags.map { it.name })
        assertEquals(listOf("Work"), b.store.read { it.entry(f) }!!.tags.map { it.name })
        assertEquals(listOf("Work"), b.store.read { it.entry(e) }!!.tags.map { it.name })
        b.store.untag(f, tags[0].id)
        assertTrue(b.store.read { it.entry(f) }!!.tags.isEmpty())
        assertEquals(1, b.store.read { it.entry(e) }!!.tags.size)
    }

    @Test fun orphansThenParentEqualsSinglePage() = runBlocking {
        val source = TestStore(now = T0)
        val e = source.store.capture(
            CaptureInput(
                "take off", T0, senses = listOf(tr("взлетать")), sentence = "The plane took off late.", highlight = Highlight(10, 8),
                source = SourceInput(SourceInput.Kind.WEB, url = "https://example.com/a?utm_source=x", title = "News"), tags = listOf("travel"),
            ),
        )
        CardDirection.entries.forEachIndexed { i, d ->
            source.store.commitAnswer(ToriId.card(e, d), if (i == 1) Rating.FORGOT else Rating.REMEMBERED, T0 + i * 1000L, 180, 900)
        }
        val records = source.records()
        val parents = setOf("entry", "card", "tag", "source", "language_pair", "settings")

        val one = TestStore(now = T0 + 1)
        one.store.applyCloudChanges(records, token = "1")
        val two = TestStore(now = T0 + 1)
        two.store.applyCloudChanges(records.filter { it.type !in parents }, token = "1")
        assertNull("orphans hidden", two.store.read { it.entry(e) })
        two.store.applyCloudChanges(records.filter { it.type in parents }, token = "2")

        fun List<String>.synced() = filter { !it.startsWith("settings") && !it.startsWith("language_pair") }
        assertEquals(one.dump().synced(), two.dump().synced())
        val detail = two.store.read { it.entry(e) }!!
        assertEquals(listOf(1, 1, 1), detail.cards.map { it.reps })
        assertEquals("News", detail.contexts.first().sourceTitle)
        assertEquals(listOf("travel"), detail.tags.map { it.name })
        val q = "SELECT id, stability, due_day FROM card ORDER BY id"
        assertEquals(source.rows(q).map { it.values.toString() }.size, one.rows(q).size)
        assertEquals(source.rows(q).map { listOf(it.id("id"), it.double("stability"), it.long("due_day")) }, one.rows(q).map { listOf(it.id("id"), it.double("stability"), it.long("due_day")) })
    }

    @Test fun deleteWinsHidesPurgesAndDropsLateChildren() = runBlocking {
        val a = TestStore(now = T0)
        val e = a.store.capture(CaptureInput("run", T0, senses = listOf(tr("бежать"))))
        val b = TestStore(now = T0)
        b.store.applyCloudChanges(a.records(), token = "1")

        val lateSense = a.store.addSense(e, tr("бегать"))
        b.store.deleteEntries(listOf(e))
        assertNull(b.store.read { it.entry(e) })
        assertEquals(0L, b.long("SELECT COUNT(*) FROM sense"))
        assertEquals(0L, b.long("SELECT COUNT(*) FROM card"))

        b.store.applyCloudChanges(listOf(a.store.read { it.record(RecordType.SENSE, lateSense) }!!), token = "2")
        assertEquals(0L, b.long("SELECT COUNT(*) FROM sense"))

        val tombstone = b.store.read { it.record(RecordType.ENTRY, e) }!!
        assertTrue(tombstone.deleted && tombstone.fields.isEmpty())
        a.store.applyCloudChanges(listOf(tombstone), token = "1")
        assertNull(a.store.read { it.entry(e) })
    }

    @Test fun syncedDeleteQueuesPurgeOwnersAfterAckAndOnSight() = runBlocking {
        val a = TestStore(now = T0)
        a.activate()
        val e = a.store.capture(CaptureInput("run", T0, senses = listOf(tr("бежать"))))
        a.store.recordSaved(a.store.pendingPush(1000).rows)
        val beforeDelete = a.records()
        a.store.deleteEntries(listOf(e))
        // Hidden until the tombstone is acked.
        assertNull(a.store.read { it.entry(e) })
        assertTrue(a.store.pendingCloudDeletes().isEmpty())
        a.store.recordSaved(a.store.pendingPush().rows)
        assertEquals(0L, a.long("SELECT COUNT(*) FROM sense"))
        assertEquals(listOf(e), a.store.pendingCloudDeletes())
        a.store.cloudDeletesDone(listOf(e))
        assertTrue(a.store.pendingCloudDeletes().isEmpty())

        // A live child of the deleted Entry seen in a later page: dropped, its owner queued (purge on sight).
        val sense = beforeDelete.first { it.type == "sense" }
        a.store.applyCloudChanges(listOf(sense))
        assertEquals(0L, a.long("SELECT COUNT(*) FROM sense"))
        assertEquals(listOf(e), a.store.pendingCloudDeletes())
    }

    @Test fun unknownFieldsAndTypesAreKeptByteFaithfully() = runBlocking {
        val s = TestStore()
        val e = s.store.capture(CaptureInput("run", T0))
        val record = s.store.read { it.record(RecordType.ENTRY, e) }!!
        val clock = HlcTimestamp(T0 + 5000, 0, 7UL)
        val future = WireJson.json.parseToJsonElement("""{"b":[1,2.5,{"z":null}],"a":"x"}""")
        val remote = record.copy(schema = 2, fields = record.fields + ("future_field" to FieldVersion(future, clock, AuthorRank.USER)))
        val unknown = SyncRecord(ToriId.v5("x"), "deck", 1, null, false, null, emptyMap())
        assertEquals(setOf("deck"), s.store.applyCloudChanges(listOf(remote, unknown), token = "1").skippedUnknownTypes)
        s.activate()
        val pushed = s.store.pendingPush().records.first { it.id == e }
        assertEquals(FieldVersion(future, clock, AuthorRank.USER), pushed.fields["future_field"])
        assertEquals(2, pushed.schema)
        val text = WireJson.encodeToString(pushed)
        assertTrue(text, text.contains(""""v":{"b":[1,2.5,{"z":null}],"a":"x"}"""))
        assertEquals(JsonObject(mapOf("future_field" to future)), s.store.read { it.word(e) }!!["extra"])
    }

    @Test fun envelopeRoundTripThroughStore() = runBlocking {
        val a = TestStore(now = T0)
        a.store.capture(
            CaptureInput("take off", T0, senses = listOf(tr("взлетать")), sentence = "It took off.", highlight = Highlight(3, 8), tags = listOf("t")),
        )
        a.store.setNewWordsPerDay(20)
        val records = a.records()
        val b = TestStore(now = T0)
        b.store.applyCloudChanges(records.map { WireJson.decodeFromString(WireJson.encodeToString(it)) })
        val back = b.records().associateBy { it.id }
        // Defaults (deterministic IDs) exist on both devices; whose rank-0 clock wins depends on random device IDs.
        for (r in records) if (r.type !in setOf("device", "language_pair", "settings")) assertEquals(r.type, r, back[r.id])
        // Integral REAL and fsrs_w values encode as integers, as on iOS.
        val settings = back.getValue(ToriId.settings)
        assertEquals(records.first { it.type == "settings" }.fields["new_words_per_day"], settings.fields["new_words_per_day"])
        assertTrue((settings.fields.getValue("fsrs_w").value as JsonArray).isNotEmpty())
        val position = records.first { it.type == "sense" }.fields.getValue("position").value
        assertEquals(JsonPrimitive(1L), position)
    }

    @Test fun incrementalAnswerEqualsFullReplayAndParamsRebuild() = runBlocking {
        val s = TestStore()
        val e = s.store.capture(CaptureInput("run", T0, senses = listOf(tr("бежать"))))
        val card = ToriId.card(e, CardDirection.RECALL)
        val answers = listOf(0 to Rating.REMEMBERED, 0 to Rating.FORGOT, 1 to Rating.REMEMBERED, 4 to Rating.REMEMBERED, 13 to Rating.FORGOT, 14 to Rating.REMEMBERED)
        for ((day, rating) in answers) s.store.commitAnswer(card, rating, T0 + day * 86_400_000L + 1, 180, 2000)
        s.store.commitAnswer(card, Rating.REMEMBERED, T0 + 2 * 86_400_000L, 180, null)

        suspend fun expected(p: FsrsParameters) = Fsrs.replay(
            card,
            s.rows("SELECT id, reviewed_at, utc_offset_min, rating FROM review_log").map {
                ReviewLogInput(it.id("id")!!, card, it.long("reviewed_at")!!, it.int("utc_offset_min")!!, Rating.of(it.int("rating")!!))
            },
            p,
        )!!
        suspend fun cached() = s.rows("SELECT * FROM card WHERE id = ?", card).single()

        var want = expected(FsrsParameters.DEFAULT)
        var row = cached()
        assertEquals(want.stability, row.double("stability")!!, 0.0)
        assertEquals(want.difficulty, row.double("difficulty")!!, 0.0)
        assertEquals(want.dueDay, row.int("due_day"))
        assertEquals(want.reps, row.int("reps"))
        assertEquals(want.lapses, row.int("lapses"))
        assertEquals(want.stage.wire, row.str("stage"))

        val p = FsrsParameters.DEFAULT.copy(desiredRetention = 0.85)
        s.store.setSchedulerParameters(p, "custom-1")
        want = expected(p)
        row = cached()
        assertEquals(want.stability, row.double("stability")!!, 0.0)
        assertEquals(want.dueDay, row.int("due_day"))
        assertEquals("custom-1", row.str("params_id"))
    }

    @Test fun cardsCreatedWhenReviewableWithClozeForHighlightedSentence() = runBlocking {
        val s = TestStore()
        val plain = s.store.capture(CaptureInput("run", T0, senses = listOf(tr("бежать")), sentence = "They walk."))
        val cloze = s.store.capture(CaptureInput("walk", T0, senses = listOf(tr("идти")), sentence = "They walk.", highlight = Highlight(5, 4)))
        val pending = s.store.capture(CaptureInput("jump", T0))
        suspend fun directions(e: ToriId) = s.store.read { it.entry(e) }!!.cards.map { it.direction }
        assertEquals(listOf(CardDirection.RECOGNITION, CardDirection.RECALL), directions(plain))
        assertEquals(CardDirection.entries, directions(cloze))
        assertTrue(directions(pending).isEmpty())
        s.store.fillAutomaticSense(pending, tr("прыгать"))
        assertEquals(listOf(CardDirection.RECOGNITION, CardDirection.RECALL), directions(pending))
        assertTrue(s.store.read { it.entry(pending) }!!.needsCheck)
        s.store.commitAnswer(ToriId.card(pending, CardDirection.RECALL), Rating.REMEMBERED, T0, 0, 1)
        assertFalse(s.store.read { it.entry(pending) }!!.needsCheck)
        assertEquals(0, JsonText.clocks(s.text("SELECT field_clocks FROM entry WHERE id = ?", pending))["needs_check"]?.u)
    }

    @Test fun nilTokenResetClearsDriveIndexInTheSameTransaction() = runBlocking {
        val s = TestStore()
        s.activate()
        val e = s.store.capture(CaptureInput("run", T0, senses = listOf(tr("бежать"))))
        val batch = s.store.pendingPush(1000)
        s.store.recordSaved(batch.rows, listOf(DriveFileIndex(file("f1"), DriveFileOwner.of("f1", batch.records))))
        s.store.applyCloudChanges(emptyList(), token = "t1", index = listOf(DriveFileIndex(file("f2"), null)))
        assertEquals(2L, s.long("SELECT COUNT(*) FROM drive_file"))
        val owners = s.store.database.driveFiles().owners("f1")
        assertEquals(listOf(e), owners.map { ToriId.fromBytes(it.owner) })
        assertTrue(owners.single().has_live)
        assertEquals(listOf("f2"), s.store.database.driveFiles().filesWithUnknownOwners().map { it.file_id })
        assertEquals(listOf("f1"), s.store.database.driveFiles().filesHolding(listOf(e.bytes)))

        s.store.setSyncState(mapOf(SyncStateKey.PAGE_TOKEN to null))
        assertNull(s.store.syncState(SyncStateKey.PAGE_TOKEN))
        assertEquals(0L, s.long("SELECT COUNT(*) FROM drive_file"))
        assertEquals(0L, s.long("SELECT COUNT(*) FROM drive_file_owner"))

        // An account switch is a nil-token reset too.
        s.store.applyCloudChanges(emptyList(), token = "t2", index = listOf(DriveFileIndex(file("f3"), emptyList())))
        s.store.setSyncState(mapOf(SyncStateKey.GENERATION to "g", SyncStateKey.DRIVE_DELETED to "1"))
        s.store.activateDrive("account-2")
        assertEquals(0L, s.long("SELECT COUNT(*) FROM drive_file"))
        assertNull(s.store.syncState(SyncStateKey.GENERATION))
        assertNull(s.store.syncState(SyncStateKey.DRIVE_DELETED))
        assertTrue(s.store.isOutboxActive())
    }

    @Test fun driveFileOwnerIndexesEntriesUnderTheirOwnId() {
        val e = ToriId.v5("e")
        val clock = HlcTimestamp(T0, 0, 1UL)
        fun rec(id: ToriId, type: String, owner: ToriId?, deleted: Boolean) = SyncRecord(
            id, type, 1, owner, deleted, null, if (deleted) emptyMap() else mapOf("x" to FieldVersion(JsonPrimitive(1), clock, AuthorRank.USER)),
        )
        val tomb = DriveFileOwner.of("f", listOf(rec(e, "entry", null, true), rec(ToriId.v5("t"), "tag", null, false)))
        assertEquals(listOf(e), tomb.map { ToriId.fromBytes(it.owner) })
        assertFalse(tomb.single().has_live)
        assertTrue(DriveFileOwner.of("f", listOf(rec(e, "entry", null, true), rec(ToriId.v5("s"), "sense", e, false))).single().has_live)
    }

    @Test fun removeAllDataRecreatesDefaultsAndClearsDriveState() = runBlocking {
        val s = TestStore()
        s.activate()
        s.store.capture(CaptureInput("run", T0, senses = listOf(tr("бежать"))))
        s.store.applyCloudChanges(emptyList(), token = "tok", index = listOf(DriveFileIndex(file("f"), emptyList())))
        s.store.removeAllDataFromDevice()
        assertNull(s.store.syncState(SyncStateKey.PAGE_TOKEN))
        assertEquals(0L, s.long("SELECT COUNT(*) FROM drive_file"))
        assertEquals(0L, s.long("SELECT COUNT(*) FROM entry"))
        assertEquals(1L, s.long("SELECT COUNT(*) FROM settings"))
        assertEquals(0, s.store.pendingRecordCount())
        assertNotNull(s.store.thisDeviceId())
    }

    @Test fun newWordsPerDayIsClamped() = runBlocking {
        val s = TestStore()
        s.store.setNewWordsPerDay(99)
        assertEquals(50L, s.long("SELECT new_words_per_day FROM settings"))
        s.store.setNewWordsPerDay(-1)
        assertEquals(0L, s.long("SELECT new_words_per_day FROM settings"))
    }

    @Test fun pageAppliedInChunksOfOneEqualsWholePage() = runBlocking {
        val source = TestStore(now = T0)
        val e = source.store.capture(CaptureInput("run", T0, senses = listOf(tr("бежать")), tags = listOf("x")))
        source.store.commitAnswer(ToriId.card(e, CardDirection.RECALL), Rating.HARD, T0, 0, 10)
        val records = source.records().filter { it.type != "device" }
        val whole = TestStore(now = T0 + 1)
        whole.store.applyCloudChanges(records)
        val chunked = TestStore(now = T0 + 1)
        for (r in records.reversed()) chunked.store.applyCloudChanges(listOf(r))
        fun List<String>.synced() = filter { !it.startsWith("settings") && !it.startsWith("language_pair") }
        assertEquals(whole.dump().synced(), chunked.dump().synced())
        assertEquals(whole.store.read { it.word(e) }, chunked.store.read { it.word(e) })
        assertEquals(whole.store.read { it.dump() }.filter { it.startsWith("entry") || it.startsWith("card") }, chunked.store.read { it.dump() }.filter { it.startsWith("entry") || it.startsWith("card") })
    }

    private fun file(id: String) = DriveFile(id, "b-$id.json", "batch", "dev", 1, "gen", T0)
}
