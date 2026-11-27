package com.toriwords.core

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.MethodSource
import kotlin.random.Random

class IdAndSyncFixtureTest {
    companion object {
        @JvmStatic fun uuidV5() = Fixtures.cases("ids/uuid-v5.json")
        @JvmStatic fun uuidV7() = Fixtures.cases("ids/uuid-v7.json")
        @JvmStatic fun byteOrder() = Fixtures.cases("ids/byte-order.json")
        @JvmStatic fun localWrite() = Fixtures.cases("hlc/local-write.json")
        @JvmStatic fun receive() = Fixtures.cases("hlc/receive.json")
        @JvmStatic fun clockAhead() = Fixtures.cases("hlc/clock-ahead.json")
        @JvmStatic fun fieldComparator() = Fixtures.cases("merge/field-comparator.json")
        @JvmStatic fun envelope() = Fixtures.cases("merge/envelope.json")

        fun state(j: JsonElement) = HlcState(j["ms"].long, j["counter"].int)
        fun node(c: FixtureCase) = c.file.getValue("node").str!!.toULong(16)
        fun field(j: JsonElement): FieldVersion<JsonElement> = WireJson.field(j) { it }
        fun envelope(j: JsonElement): Envelope<JsonElement> = WireJson.envelope(j) { it }
    }

    @ParameterizedTest(name = "{0}") @MethodSource
    fun uuidV5(c: FixtureCase) {
        assertEquals(c.file.getValue("namespace").str, ToriId.namespace.toString())
        val expected = c["uuid"].str
        assertEquals(expected, ToriId.v5(c["name"].str!!).toString())
        val p = c["params"]
        val record = c["record"].str
        val actual = when (record) {
            "languagePair" -> ToriId.languagePair(p["native"].str!!, p["target"].str!!)
            "settings" -> ToriId.settings
            "card" -> ToriId.card(id(p["entryId"]), CardDirection.fromWire(p["direction"].str!!)!!)
            "source" -> ToriId.source(p["urlKey"].str!!)
            "entryTag" -> ToriId.entryTag(id(p["entryId"]), id(p["tagId"]))
            "autoSense" -> ToriId.autoSense(id(p["entryId"]), p["ordinal"].int)
            else -> null // importedReviewLog: a helper comes with Anki import (later); the v5 name is checked above
        }
        if (record != "importedReviewLog") assertEquals(expected, actual?.toString())
    }

    @ParameterizedTest(name = "{0}") @MethodSource
    fun uuidV7(c: FixtureCase) {
        val id = ToriId.v7(c["unixMs"].long, c["randA"].str!!.toInt(16), c["randB"].str!!.toULong(16))
        assertEquals(c["uuid"].str, id.toString())
        assertEquals(id, ToriId.parse(c["uuid"].str!!))
        assertEquals(id, ToriId.fromBytes(id.bytes))
    }

    @ParameterizedTest(name = "{0}") @MethodSource
    fun byteOrder(c: FixtureCase) {
        if (c.has("a")) {
            val a = id(c["a"])
            val b = id(c["b"])
            assertEquals(c["expected"].int, a.compareTo(b).coerceIn(-1, 1))
            assertEquals(a < b, java.util.Arrays.compareUnsigned(a.bytes, b.bytes) < 0)
        } else {
            assertEquals(c["expected"].array.map { it.str }, c["input"].array.map(::id).sorted().map { it.toString() })
        }
    }

    @Test
    fun v7FromInjectedRandomness() {
        val id = ToriId.v7(1_762_790_400_000, Random(1))
        assertTrue(id.toString().startsWith("019a6e7e-e000-7"))
        assertTrue((id.bytes[8].toInt() and 0xF0) shr 4 in 0x8..0xb)
    }

    @ParameterizedTest(name = "{0}") @MethodSource
    fun localWrite(c: FixtureCase) {
        val s = state(c["state"])
        val clock = s.localWrite(c["now"].long, node(c))
        assertEquals(state(c["expected"]["state"]), s)
        assertEquals(c["expected"]["clock"].str, clock.toString())
        assertEquals(clock, HlcTimestamp.parse(clock.toString()))
    }

    @ParameterizedTest(name = "{0}") @MethodSource
    fun receive(c: FixtureCase) {
        if (c["type"].str == "serverSkew") {
            val ok = HlcState.serverAccepts(HlcTimestamp.parse(c["clock"].str!!)!!, c["serverTime"].long)
            assertEquals(c["expected"]["result"].str, if (ok) "accepted" else "clock_skew")
        } else {
            val s = state(c["state"])
            s.receive(HlcTimestamp.parse(c["remote"].str!!)!!, c["now"].long)
            assertEquals(state(c["expected"]["state"]), s)
        }
    }

    @ParameterizedTest(name = "{0}") @MethodSource
    fun clockAhead(c: FixtureCase) {
        val s = state(c["state"])
        val clocks = s.recoverIfAhead(c["lastServerTime"].long, c["now"].long, node(c), c["pendingFields"].int)
        val e = c["expected"]
        assertEquals(e["reset"].bool, clocks != null)
        assertEquals(state(e["state"]), s)
        assertEquals(e["restampedClocks"].array.map { it.str }, (clocks ?: emptyList()).map { it.toString() })
    }

    @ParameterizedTest(name = "{0}") @MethodSource
    fun fieldComparator(c: FixtureCase) {
        val local = field(c["local"])
        val remote = field(c["remote"])
        assertEquals(if (c["expected"].str == "local") local else remote, FieldVersion.merge(local, remote))
    }

    @ParameterizedTest(name = "{0}") @MethodSource
    fun envelope(c: FixtureCase) {
        val local = envelope(c["local"])
        val remote = envelope(c["remote"])
        val expected = envelope(c["expected"])
        assertEquals(expected, Envelope.merge(local, remote))
        assertEquals(expected, Envelope.merge(remote, local))
        if (c.has("remotePartial")) assertEquals(expected, Envelope.merge(local, envelope(c["remotePartial"])))
    }

    @Test
    fun syncRecordRoundTripsWithExplicitNulls() {
        val text = """{"id":"0192f3c1-7a4e-7cc3-9b1e-3f5a2d6c8e01","type":"entry","schema":1,"owner":null,""" +
            """"deleted":false,"mergedInto":null,"fields":{"text":{"v":"take off","c":"0192f3c17a4e00001a2b3c4d5e6f7081","u":1},""" +
            """"needs_check":{"v":true,"c":"0192f3c1802000001a2b3c4d5e6f7081","u":0},""" +
            """"fsrs_w":{"v":[0.212,1],"c":"0192f3c1802000001a2b3c4d5e6f7081","u":0},"ipa":{"v":null,"c":"0192f3c1802000001a2b3c4d5e6f7081","u":0}}}"""
        val record = WireJson.decodeFromString(text)
        assertEquals(JsonPrimitive("take off"), record.fields.getValue("text").value)
        assertEquals(JsonPrimitive(true), record.fields.getValue("needs_check").value)
        assertEquals("[0.212,1]", record.fields.getValue("fsrs_w").value.toString())
        assertEquals(JsonNull, record.fields.getValue("ipa").value)
        assertEquals(AuthorRank.USER, record.fields.getValue("text").rank)
        assertNull(record.owner)
        assertEquals(text, WireJson.encodeToString(record))
    }

    @Test
    fun envelopeDecodeDefaultsMissingOptionalKeys() {
        val record = WireJson.decode(
            WireJson.json.parseToJsonElement("""{"id":"0192f3c1-7a4e-7cc3-9b1e-3f5a2d6c8e01","type":"tag","schema":2}""") as JsonObject,
        )
        assertNotNull(record)
        assertEquals(false, record.deleted)
        assertTrue(record.fields.isEmpty())
    }
}
