package com.toriwords.sync

import com.toriwords.core.WireJson
import com.toriwords.store.CaptureInput
import com.toriwords.store.NewSense
import com.toriwords.store.RecordType
import com.toriwords.store.SyncStateKey
import com.toriwords.store.allRecords
import com.toriwords.store.capture
import com.toriwords.store.deleteEntries
import com.toriwords.store.liveEntryCount
import com.toriwords.store.syncState
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Drive mapping rules (doc 38 §11.2) against [DriveFake]. */
@RunWith(RobolectricTestRunner::class)
class DriveSyncTest {
    private var ms = 1_762_776_000_000L
    private val drive = DriveFake { ms }

    private suspend fun device(name: String, vararg words: String): Device {
        val d = Device(name, drive, { ms }, 0)
        d.launch()
        for (w in words) d.store.capture(CaptureInput(term = w, capturedAt = ms, senses = listOf(NewSense("t-$w"))))
        return d
    }

    private fun tick() {
        ms += 1_000
    }

    private fun files(kind: String) = drive.files("alice").map { it.file }.filter { it.kind == kind }
    private fun generation() = files(DriveFormat.GENERATION).single().generation!!

    private fun putGeneration(uuid: String) = DriveFormat.generation(uuid).let { drive.put("alice", it.name, it.appProperties, it.bytes) }

    private fun putFile(json: JsonObject, generation: String = generation(), layout: String = "1", deviceId: String = "00000000000000cc") =
        drive.put(
            "alice", "b-$deviceId-1.json.gz",
            mapOf("layout" to layout, "generation" to generation, "kind" to DriveFormat.BATCH, "deviceId" to deviceId, "seq" to "1", "part" to "0"),
            DriveFormat.gzip(json),
        )

    private fun body(records: List<JsonObject>, generation: String = generation(), extra: Map<String, JsonPrimitive> = emptyMap()) = JsonObject(
        mapOf(
            "layout" to JsonPrimitive(1), "generation" to JsonPrimitive(generation), "kind" to JsonPrimitive("batch"),
            "deviceId" to JsonPrimitive("00000000000000cc"), "seq" to JsonPrimitive(1), "part" to JsonPrimitive(0),
            "parts" to JsonPrimitive(1), "records" to JsonArray(records),
        ) + extra,
    )

    private val Device.phase get() = engine.status.value.phase

    @Test fun compactionWritesSnapshotDeletesCoversAndRetriesFailedDeletes() = runBlocking {
        val a = device("A", "run")
        a.turnOn("alice")
        val other = device("B", "walk").store.read { it.allRecords() }
        repeat(DriveCloud.COMPACTION_THRESHOLD) { i ->
            val upload = DriveFormat.batch(generation(), "00000000000000bb", i + 1L, other)
            drive.put("alice", upload.name, upload.appProperties, upload.bytes)
        }
        tick()
        drive.fail(DriveFake.Op.Delete, DriveError.Network)
        a.sync()

        assertEquals(SyncPhase.WaitingForNetwork, a.phase)
        val snapshot = files(DriveFormat.SNAPSHOT).single()
        val covers = DriveFormat.Body.decode(drive.files("alice").first { it.file.id == snapshot.id }.bytes).covers
        assertEquals(DriveCloud.COMPACTION_THRESHOLD + 1, covers.size) // the 200 batches and A's own
        assertEquals(covers.size, a.store.database.driveFiles().pendingDeletes().size)

        tick()
        a.sync()
        assertEquals(SyncPhase.Idle, a.phase)
        assertTrue(files(DriveFormat.BATCH).isEmpty())
        assertTrue(a.store.database.driveFiles().pendingDeletes().isEmpty())

        // A fresh device gets everything from the snapshot alone.
        val c = device("C")
        c.turnOn("alice")
        assertEquals(2, c.store.liveEntryCount())
    }

    @Test fun duplicateGenerationsKeepEarliestAndNeverDeleteDrive() = runBlocking {
        val first = putGeneration("g-first")
        putGeneration("g-second") // same createdTime: the lower fileId wins
        val a = device("A", "run")
        a.turnOn("alice")
        assertEquals(SyncPhase.Idle, a.phase)
        assertEquals("g-first", a.store.syncState(SyncStateKey.GENERATION))
        assertEquals(listOf(first.id), files(DriveFormat.GENERATION).map { it.id })
    }

    @Test fun earlierGenerationIsAdoptedSilentlyAndEverythingResent() = runBlocking {
        val a = device("A", "run")
        tick()
        a.turnOn("alice")
        val mine = a.store.syncState(SyncStateKey.GENERATION)
        ms -= 500 // another device's marker created first (creation race)
        putGeneration("g-earlier")
        ms += 1_500
        a.sync()

        assertEquals(SyncPhase.Idle, a.phase)
        assertEquals("g-earlier", a.store.syncState(SyncStateKey.GENERATION))
        assertNotEquals(mine, "g-earlier")
        val resent = files(DriveFormat.BATCH).filter { it.generation == "g-earlier" }
        assertTrue("records re-sent under the winner", resent.isNotEmpty())
    }

    @Test fun laterOrMissingGenerationMeansDriveDataDeleted() = runBlocking {
        val a = device("A", "run")
        a.turnOn("alice")
        drive.deleteAll("alice")
        tick()
        putGeneration("g-recreated")
        a.sync()
        assertEquals(SyncPhase.DriveDeleted, a.phase)
        assertEquals(1, a.store.liveEntryCount())

        a.engine.backUpAgain()
        assertEquals(SyncPhase.Idle, a.phase)
        assertEquals("g-recreated", a.store.syncState(SyncStateKey.GENERATION))
    }

    @Test fun strayFilesOfADeletedGenerationAreNeverAppliedAndDeleted() = runBlocking {
        val ghost = device("G", "ghost").store.read { it.allRecords() }.map(WireJson::encode)
        val stray = putFile(body(ghost, generation = "g-old"), generation = "g-old")
        tick()
        val a = device("A", "run")
        a.turnOn("alice")
        assertEquals(SyncPhase.Idle, a.phase)
        assertEquals(1, a.store.liveEntryCount())
        assertFalse(drive.files("alice").any { it.file.id == stray.id })
    }

    @Test fun purgeRewritesRawJsonKeepsUnknownContentAndDeletesEmptiedFiles() = runBlocking {
        val a = device("A", "run")
        a.turnOn("alice")
        val run = a.store.read { r -> r.allRecords().first { it.type == RecordType.ENTRY.name } }
        val sense = a.store.read { r -> r.allRecords().first { it.type == "sense" && it.owner == run.id } }
        val deck = buildJsonObject {
            put("id", "0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b")
            put("type", "deck")
            put("schema", 1)
            put("fields", JsonObject(emptyMap()))
        }
        val liveEntry = JsonObject(WireJson.encode(run) + ("future" to JsonPrimitive(1)))
        val mixed = putFile(body(listOf(liveEntry, deck), extra = mapOf("hint" to JsonPrimitive("kept"))))
        val onlySense = putFile(body(listOf(WireJson.encode(sense))), deviceId = "00000000000000dd")
        tick()
        a.sync()

        a.store.deleteEntries(listOf(run.id))
        tick()
        a.sync()

        assertEquals(SyncPhase.Idle, a.phase)
        val rewritten = DriveFormat.Body.decode(drive.files("alice").first { it.file.id == mixed.id }.bytes)
        assertEquals(JsonPrimitive("kept"), rewritten.json["hint"])
        assertEquals(listOf("deck"), rewritten.raw.map { (it as JsonObject)["type"].let { t -> (t as JsonPrimitive).content } })
        assertFalse("emptied file deleted", drive.files("alice").any { it.file.id == onlySense.id })
        assertTrue("no live envelope of the deleted entry left", drive.envelopes("alice").none { it.id == run.id && !it.deleted })
        assertTrue(drive.envelopes("alice").none { it.owner == run.id })
    }

    @Test fun newerLayoutFilesAreNeverDownloadedRewrittenOrDeleted() = runBlocking {
        val a = device("A", "run")
        a.turnOn("alice")
        // Not even gzip: downloading it would fail the cycle.
        val future = drive.put(
            "alice", "b-x-1.json.gz",
            mapOf("layout" to "2", "generation" to generation(), "kind" to DriveFormat.BATCH, "deviceId" to "00000000000000ee", "seq" to "1", "part" to "0"),
            byteArrayOf(1, 2, 3),
        )
        tick()
        a.sync()
        val b = device("B")
        b.turnOn("alice")
        assertEquals(SyncPhase.Idle, a.phase)
        assertEquals(SyncPhase.Idle, b.phase)
        assertEquals(1, b.store.liveEntryCount())
        assertTrue(drive.files("alice").any { it.file.id == future.id && it.bytes.contentEquals(byteArrayOf(1, 2, 3)) })
    }

    @Test fun expiredPageTokenFallsBackToNilTokenFetch() = runBlocking {
        val a = device("A", "run")
        a.turnOn("alice")
        val b = device("B")
        b.turnOn("alice")
        a.store.capture(CaptureInput(term = "walk", capturedAt = ms, senses = listOf(NewSense("t"))))
        tick()
        a.sync()
        drive.invalidateTokens("alice")
        drive.calls.clear()
        b.sync()
        assertEquals(SyncPhase.Idle, b.phase)
        assertEquals(2, b.store.liveEntryCount())
        assertTrue(DriveFake.Op.StartToken in drive.calls)
    }

    @Test fun backgroundNeedsResolutionSkipsAndSilentAccountChangeNeverSwitches() = runBlocking {
        val a = device("A", "run")
        a.turnOn("alice")
        val before = a.engine.status.value
        a.gate.result = AuthResult.NeedsResolution
        drive.calls.clear()
        a.engine.sync(SyncTrigger.Periodic, foreground = false)
        assertTrue("no Drive calls", drive.calls.isEmpty())
        assertEquals(before, a.engine.status.value)
        a.engine.sync(SyncTrigger.Foreground, foreground = true)
        assertEquals(SyncPhase.AccessRemoved, a.phase)

        a.gate.result = AuthResult.Ok
        a.link!!.account = "bob" // a silent token now belongs to another account
        a.store.capture(CaptureInput(term = "walk", capturedAt = ms, senses = listOf(NewSense("t"))))
        a.engine.sync(SyncTrigger.Foreground, foreground = true)
        assertEquals(SyncPhase.AccessRemoved, a.phase)
        assertEquals(SyncEngine.accountHash(DriveUser("alice", null, null)), a.store.syncState(SyncStateKey.DRIVE_ACCOUNT))
        assertTrue("nothing written to bob's Drive", drive.files("bob").isEmpty())
    }

    @Test fun errorsMapToStatus() = runBlocking {
        val a = device("A", "run")
        a.turnOn("alice")
        suspend fun after(op: DriveFake.Op, e: DriveError): SyncPhase {
            a.store.capture(CaptureInput(term = "w${ms}", capturedAt = ms, senses = listOf(NewSense("t"))))
            drive.fail(op, e)
            tick()
            a.sync()
            return a.phase
        }
        assertEquals(SyncPhase.AccessRemoved, after(DriveFake.Op.About, DriveError.NotAuthenticated))
        assertEquals(SyncPhase.QuotaFull, after(DriveFake.Op.Create, DriveError.QuotaExceeded))
        assertEquals(SyncPhase.WaitingForNetwork, after(DriveFake.Op.Changes, DriveError.Network))
        assertEquals(SyncPhase.Idle, after(DriveFake.Op.Create, DriveError.RateLimited(1_000)))
        // 413 halves the batch and the records still go out.
        assertEquals(SyncPhase.Idle, after(DriveFake.Op.Create, DriveError.TooLarge))
        a.sync()
        assertEquals(0, a.engine.status.value.pendingCount)
    }

    @Test fun backoffGrowsToFifteenMinutesWithJitter() {
        assertEquals(5_000L, Backoff.delayMs(0, 0.5))
        assertEquals(4_000L, Backoff.delayMs(0, 0.0))
        assertEquals(12_000L, Backoff.delayMs(1, 1.0))
        assertEquals(900_000L, Backoff.delayMs(30, 0.5))
    }
}
