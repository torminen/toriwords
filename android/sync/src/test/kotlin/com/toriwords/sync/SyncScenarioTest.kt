package com.toriwords.sync

import androidx.test.core.app.ApplicationProvider
import com.toriwords.core.AuthorRank
import com.toriwords.core.CardDirection
import com.toriwords.core.FieldVersion
import com.toriwords.core.FsrsParameters
import com.toriwords.core.HlcTimestamp
import com.toriwords.core.Rating
import com.toriwords.core.SyncRecord
import com.toriwords.core.TextKey
import com.toriwords.core.ToriId
import com.toriwords.store.CaptureInput
import com.toriwords.store.EntryStatus
import com.toriwords.store.KeyEditResult
import com.toriwords.store.NewSense
import com.toriwords.store.RecordType
import com.toriwords.store.SenseSource
import com.toriwords.store.SourceInput
import com.toriwords.store.SyncStateKey
import com.toriwords.store.ToriStore
import com.toriwords.store.allTags
import com.toriwords.store.capture
import com.toriwords.store.commitAnswer
import com.toriwords.store.deleteEntries
import com.toriwords.store.dump
import com.toriwords.store.editSense
import com.toriwords.store.entry
import com.toriwords.store.fillAutomaticSense
import com.toriwords.store.launch
import com.toriwords.store.pendingRecordCount
import com.toriwords.store.record
import com.toriwords.store.setEntryIpa
import com.toriwords.store.setEntryNote
import com.toriwords.store.setEntryText
import com.toriwords.store.setNewWordsPerDay
import com.toriwords.store.setSchedulerParameters
import com.toriwords.store.setStatus
import com.toriwords.store.syncState
import com.toriwords.store.tag
import com.toriwords.store.untag
import com.toriwords.store.word
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.ParameterizedRobolectricTestRunner
import java.io.File
import java.nio.file.Files

/** `fixtures/sync/` (read in place): the real ToriStore + SyncEngine per simulated device, against [DriveFake]. */
@RunWith(ParameterizedRobolectricTestRunner::class)
class SyncScenarioTest(private val name: String, private val case: JsonElement) {
    companion object {
        @JvmStatic
        @ParameterizedRobolectricTestRunner.Parameters(name = "{0}")
        fun cases(): List<Array<Any>> {
            val dir = File(System.getProperty("fixturesDir") ?: error("fixturesDir system property not set"), "sync")
            return dir.listFiles { f -> f.name.endsWith(".json") }!!.sortedBy { it.name }.flatMap { f ->
                Json.parseToJsonElement(f.readText()).jsonObject.getValue("cases").jsonArray.map { c ->
                    arrayOf<Any>(c["id"].str!!, c)
                }
            }
        }
    }

    @Test fun scenario() = runBlocking {
        val world = World(case)
        for ((i, step) in case["steps"].array.withIndex()) world.run(step, i)
        world.finishRaces()
        world.check(case["expected"])
    }
}

/** A simulated device: a real store on its own database and its engine, against one [DriveFake]. */
class Device(val name: String, val drive: DriveFake, val clock: () -> Long, var offsetMs: Long) {
    val now = { clock() + offsetMs }
    val store: ToriStore = ToriStore.inMemory(ApplicationProvider.getApplicationContext()) { now() }
    var gate = FakeGate()
    var link: DriveFake.Link? = null
    var engine = engine(400)

    suspend fun launch() {
        val dir = Files.createTempDirectory("device").toFile()
        store.launch(File(dir, "marker"), name)
        engine.start()
    }

    fun engine(applyChunk: Int) = SyncEngine(
        store, gate, NeverRetry, link, "1.0.0", now = now, sleep = { awaitCancellation() }, jitter = { 0.5 }, applyChunk = applyChunk,
    )

    /** Turn-on for `account` (the identity rule, the account switch when it differs), then a sync. */
    suspend fun turnOn(account: String, applyChunk: Int = 400) {
        val l = drive.Link(account).also { link = it }
        engine = engine(applyChunk).also { it.start() }
        engine.turnOn(l)
    }

    suspend fun sync() = engine.sync(SyncTrigger.SyncNow, foreground = true)
}

class FakeGate(var result: AuthResult = AuthResult.Ok) : TokenGate {
    override suspend fun ensureAuthorized(foreground: Boolean) = result
}

/** Retries never fire in tests (the iOS runner's sleep throws): every sync is a fixture step. */
val NeverRetry = CoroutineScope(Dispatchers.Unconfined)

private class World(c: JsonElement) {
    val start = c["start"].long
    var ms = start
    val drive = DriveFake { ms }
    val devices = c["devices"].jsonObject.entries.sortedBy { it.key }.associate { (name, cfg) ->
        name to Device(name, drive, { ms }, (cfg["clockOffsetSec"].intOrNull ?: 0) * 1000L)
    }
    val aliases = mutableMapOf<String, ToriId>()
    val raced = mutableSetOf<Device>()

    init {
        runBlocking { devices.values.forEach { it.launch() } }
    }

    suspend fun entry(d: Device, alias: String): ToriId {
        val id = aliases[alias] ?: error("unknown alias $alias")
        return d.store.read { it.sql.id("SELECT canonical_id FROM entry WHERE id = ?", id) } ?: id
    }

    suspend fun run(s: JsonElement, index: Int) {
        ms = start + s["t"].long * 1000
        val op = s["op"].str!!
        if (op == "upgradeSchema") return upgrade(s)
        val d = devices[s["device"].str] ?: error("step $index: device")
        val store = d.store
        val at = ms + d.offsetMs
        when (op) {
            "capture" -> {
                val id = store.capture(
                    CaptureInput(
                        term = s["term"].str!!, capturedAt = at, senses = s["translations"].array.map { NewSense(it.str!!) },
                        sentence = s["sentence"].str, source = s["url"].str?.let { SourceInput(SourceInput.Kind.WEB, it) },
                        tags = s["tags"].array.map { it.str!! },
                    ),
                )
                s["as"].str?.let { aliases[it] = id }
            }
            "editField" -> {
                val id = entry(d, s["entry"].str!!)
                val value = s["value"].str
                when (s["field"].str) {
                    "text" -> store.setEntryText(id, value!!)
                    "note" -> store.setEntryNote(id, value)
                    "ipa" -> store.setEntryIpa(id, value)
                    "translation" -> {
                        val sense = store.read { it.entry(id) }!!.senses.first()
                        store.editSense(sense.id, value, sense.definition, sense.partOfSpeech)
                    }
                    else -> error("step $index: unknown field")
                }
            }
            "enrich" -> {
                val id = entry(d, s["entry"].str!!)
                s["translation"].str?.let { store.fillAutomaticSense(id, NewSense(it, source = SenseSource.MT_APPLE)) }
                s["ipa"].str?.let { store.setEntryIpa(id, it, AuthorRank.AUTOMATIC) }
            }
            "review" -> {
                val id = entry(d, s["entry"].str!!)
                val dir = CardDirection.fromWire(s["direction"].str ?: "recognition")!!
                val rating = if (s["rating"].str == "forgot") Rating.FORGOT else Rating.REMEMBERED
                store.commitAnswer(ToriId.card(id, dir), rating, at, 0, 2000)
            }
            "exclude" -> store.setStatus(listOf(entry(d, s["entry"].str!!)), if (s["reason"].str == "paused") EntryStatus.PAUSED else EntryStatus.KNOWN)
            "resume" -> store.setStatus(listOf(entry(d, s["entry"].str!!)), EntryStatus.ACTIVE)
            "delete" -> store.deleteEntries(listOf(entry(d, s["entry"].str!!)))
            "tag" -> store.tag(listOf(entry(d, s["entry"].str!!)), s["name"].str!!)
            "untag" -> {
                val key = TextKey.tagKey(s["name"].str!!)
                val tag = store.read { it.allTags() }.first { TextKey.tagKey(it.name) == key }
                store.untag(entry(d, s["entry"].str!!), tag.id)
            }
            "mergeByEdit" -> assertEquals("step $index", KeyEditResult.Saved, store.setEntryText(entry(d, s["entry"].str!!), s["text"].str!!, mergeIfDuplicate = true))
            "setSettings" -> {
                s["newWordsPerDay"].intOrNull?.let { store.setNewWordsPerDay(it) }
                s["desiredRetention"].doubleOrNull?.let { r ->
                    store.setSchedulerParameters(FsrsParameters.DEFAULT.copy(desiredRetention = r), "custom-${(r * 100).toInt()}")
                }
            }
            // Adjustments 1 and 3: one namespace per account; `limit` = envelopes per applied chunk (and changes per page).
            "enableSync" -> withPageLimit(s) { d.turnOn(s["account"].str!!, s["limit"].intOrNull ?: 400) }
            "sync" -> {
                // Adjustment 4: the racer's whole cycle runs right before this device's next upload.
                s["racedBy"].str?.let { other ->
                    val racer = devices.getValue(other)
                    drive.beforeNextUpload { racer.sync() }
                    raced += d
                }
                withPageLimit(s) { d.sync() }
            }
            "cloudOff" -> d.engine.turnOff()
            // A silent token never switches accounts: the switch is the explicit Turn-on flow.
            "cloudSwitch" -> d.turnOn(s["to"].str!!)
            "deleteCloudData" -> if (s["inSettings"].bool == true) drive.deleteAll(d.link!!.account) else assertTrue(d.engine.deleteDriveData())
            "backUpAgain" -> d.engine.backUpAgain()
            "network" -> d.link?.online = s["online"].bool!!
            "setClock" -> d.offsetMs = s["offsetSec"].long * 1000
            else -> error("step $index: unknown op $op")
        }
    }

    /** Adjustment 4: the raced device converges on its next pull. */
    suspend fun finishRaces() {
        for (d in raced) d.sync()
    }

    private suspend fun withPageLimit(s: JsonElement, body: suspend () -> Unit) {
        val saved = drive.pageLimit
        s["limit"].intOrNull?.let { drive.pageLimit = it }
        body()
        drive.pageLimit = saved
    }

    /** Adjustment 6: a newer client (node `feedfacecafebeef`) wrote a batch with unknown fields / types / schema. */
    fun upgrade(s: JsonElement) {
        val account = s["account"].str!!
        val node = 0xfeedfacecafebeefUL
        val clock = HlcTimestamp(ms, 0, node)
        val records = s["records"].array.map { r ->
            val idText = r["id"].str!!
            SyncRecord(
                id = aliases[idText] ?: ToriId.parse(idText)!!, type = r["type"].str!!, schema = r["schema"].intOrNull ?: 1,
                owner = r["owner"].str?.let { aliases[it] ?: ToriId.parse(it) }, deleted = false, mergedInto = null,
                fields = r["fields"].jsonObject.mapValues { (_, f) ->
                    val v = f["v"].let { if (it is JsonObject) JsonNull else it }
                    FieldVersion(v, clock, AuthorRank.fromWire(f["u"].intOrNull ?: 1)!!)
                },
            )
        }
        val generation = drive.files(account).map { it.file }.filter { it.kind == DriveFormat.GENERATION }.minBy { it.createdTime }.generation!!
        val upload = DriveFormat.batch(generation, "feedfacecafebeef", 1, records)
        drive.put(account, upload.name, upload.appProperties, upload.bytes)
    }

    // Expectations

    suspend fun check(e: JsonElement) {
        for ((name, exp) in e["devices"].obj) checkDevice(devices.getValue(name), exp)
        for ((account, exp) in e["cloud"].obj) checkCloud(account, exp)
        val converged = e["converged"].array.map { devices.getValue(it.str!!) }
        val reference = converged.firstOrNull()?.store?.read { it.dump() } ?: return
        for (d in converged.drop(1)) {
            val other = d.store.read { it.dump() }
            assertEquals(
                "${d.name} differs from ${converged.first().name}: only ${d.name} ${(other - reference.toSet()).sorted()} only ${converged.first().name} ${(reference - other.toSet()).sorted()}",
                reference, other,
            )
        }
    }

    suspend fun checkDevice(d: Device, exp: JsonElement) {
        val store = d.store
        if (exp["words"] !is JsonNull) {
            val ids = store.read { it.sql.ids("SELECT id FROM entry WHERE deleted = 0 AND merged_into IS NULL") }
            val actual = ids.map { id -> store.read { it.word(id) }!! }.associateBy { it.getValue("text").str!! }
            val expected = exp["words"].array
            assertEquals("${d.name}: words", expected.map { it["text"].str!! }.toSet(), actual.keys)
            for (w in expected) {
                val a = actual.getValue(w["text"].str!!)
                for ((k, v) in w.jsonObject) assertEquals("${d.name}: ${w["text"].str}.$k", v, a[k])
            }
        }
        if (exp["settings"] !is JsonNull) {
            val row = store.read { it.sql.row("SELECT * FROM settings WHERE id = ?", ToriId.settings) }
            exp["settings"]["newWordsPerDay"].intOrNull?.let { assertEquals("${d.name}: newWordsPerDay", it.toLong(), (row?.get("new_words_per_day") as Number?)?.toLong()) }
            exp["settings"]["desiredRetention"].doubleOrNull?.let { assertEquals("${d.name}: desiredRetention", it, (row?.get("desired_retention") as Number?)?.toDouble()) }
        }
        val sync = exp["sync"]
        if (sync !is JsonNull) {
            val status = d.engine.status.value
            sync["state"].str?.let { assertEquals("${d.name}: state $status", it, stateName(status)) }
            // Adjustment 1: `user` = the account whose hash is the stored `driveAccount`.
            if ("user" in sync.obj) {
                val expected = sync["user"].str?.let { SyncEngine.accountHash(DriveUser(it, null, null)) }
                assertEquals("${d.name}: user", expected, store.syncState(SyncStateKey.DRIVE_ACCOUNT))
            }
            sync["outbox"].intOrNull?.let { assertEquals("${d.name}: outbox", it, store.pendingRecordCount()) }
        }
        for (alias in exp["tombstones"].array.map { it.str!! }) {
            val r = store.read { it.record(RecordType.ENTRY, aliases.getValue(alias)) }
            assertTrue("${d.name}: $alias is not a value-less tombstone", r?.deleted == true && r.fields.isEmpty())
        }
    }

    /** Adjustment 5: state names. */
    fun stateName(s: SyncStatus) = when (s.phase) {
        SyncPhase.Idle -> if (s.lastSyncAt != null) "synced" else "idle"
        SyncPhase.Syncing -> "syncing"
        SyncPhase.WaitingForNetwork -> "waitingForNetwork"
        SyncPhase.Off -> "iCloudOff"
        SyncPhase.QuotaFull -> "quotaFull"
        SyncPhase.DriveDeleted -> "cloudDeleted"
        else -> s.phase.name
    }

    /** Adjustment 2: every layout-1 file's envelopes folded per id, then counted. */
    fun checkCloud(account: String, exp: JsonElement) {
        assertTrue("cloud $account: no files", drive.exists(account))
        val records = drive.records(account).values
        if (exp["entries"] !is JsonNull) {
            val entries = records.filter { it.type == "entry" }
            assertEquals("cloud $account: live", exp["entries"]["live"].intOrNull, entries.count { !it.deleted && it.mergedInto == null })
            assertEquals("cloud $account: deleted", exp["entries"]["deleted"].intOrNull, entries.count { it.deleted })
            assertEquals("cloud $account: merged", exp["entries"]["merged"].intOrNull, entries.count { !it.deleted && it.mergedInto != null })
        }
        val all = drive.envelopes(account)
        for (alias in exp["purged"].array.map { it.str!! }) {
            val id = aliases.getValue(alias)
            assertTrue("cloud $account: children of $alias left", records.none { it.owner == id })
            records.firstOrNull { it.id == id }?.let { assertTrue("cloud $account: $alias is not a value-less tombstone", it.deleted && it.fields.isEmpty()) }
            assertTrue("cloud $account: a file still holds a live envelope of $alias", all.none { it.id == id && !it.deleted })
        }
        for ((type, n) in exp["types"].obj) assertEquals("cloud $account: $type count", n.intOrNull, records.count { it.type == type })
    }
}

private operator fun JsonElement.get(key: String): JsonElement = (this as? JsonObject)?.get(key) ?: JsonNull
private val JsonElement.str: String? get() = (this as? JsonPrimitive)?.takeIf { it.isString }?.content
private val JsonElement.intOrNull: Int? get() = (this as? JsonPrimitive)?.intOrNull
private val JsonElement.doubleOrNull: Double? get() = (this as? JsonPrimitive)?.doubleOrNull
private val JsonElement.long: Long get() = (this as JsonPrimitive).content.toLong()
private val JsonElement.bool: Boolean? get() = (this as? JsonPrimitive)?.booleanOrNull
private val JsonElement.array: List<JsonElement> get() = (this as? JsonArray).orEmpty()
private val JsonElement.obj: Map<String, JsonElement> get() = (this as? JsonObject).orEmpty()
