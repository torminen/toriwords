package com.toriwords.sync

import com.toriwords.core.SyncRecord
import com.toriwords.core.ToriId
import com.toriwords.core.WireJson
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import java.io.ByteArrayOutputStream
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

/** Drive file format (doc 38 §11.2): gzip JSON bodies with `appProperties` that classify a file without downloading it. */
object DriveFormat {
    const val LAYOUT = 1
    const val BATCH = "batch"
    const val SNAPSHOT = "snapshot"
    const val GENERATION = "generation"
    const val GENERATION_NAME = "generation.json"

    const val MAX_BATCH_RECORDS = 300
    const val MAX_BATCH_BYTES = 2_000_000
    const val MAX_RECORD_BYTES = 64 * 1024
    const val MAX_SNAPSHOT_RECORDS = 5_000
    const val MAX_SNAPSHOT_BYTES = 20_000_000

    /** A file to upload. */
    class Upload(val name: String, val appProperties: Map<String, String>, val bytes: ByteArray)

    /** A covered file: `{fileId, name}` (fileId authoritative). */
    data class Cover(val fileId: String, val name: String)

    fun batch(generation: String, deviceId: String, seq: Long, records: List<SyncRecord>): Upload {
        val props = props(BATCH, generation, deviceId, "seq", seq.toString(), 0)
        return Upload("b-$deviceId-$seq.json.gz", props, gzip(body(props, parts = 1, covers = null, records = records.map(WireJson::encode))))
    }

    fun snapshotPart(generation: String, deviceId: String, n: Long, part: Int, parts: Int, covers: List<Cover>, records: List<SyncRecord>): Upload {
        val props = props(SNAPSHOT, generation, deviceId, "n", n.toString(), part)
        val body = body(props, parts, covers.takeIf { part == 0 }, records.map(WireJson::encode))
        return Upload("s-$deviceId-$n-$part.json.gz", props, gzip(body))
    }

    fun generation(uuid: String): Upload = Upload(
        GENERATION_NAME, mapOf("layout" to "$LAYOUT", "kind" to GENERATION, "generation" to uuid),
        WireJson.json.encodeToString(JsonObject.serializer(), buildJsonObject { put("generation", uuid) }).toByteArray(),
    )

    /** Snapshot parts: ≤ 5,000 envelopes and ≤ 20 MB uncompressed each. */
    fun snapshotParts(records: List<SyncRecord>): List<List<SyncRecord>> = split(records, MAX_SNAPSHOT_RECORDS, MAX_SNAPSHOT_BYTES)

    fun split(records: List<SyncRecord>, maxRecords: Int, maxBytes: Int): List<List<SyncRecord>> {
        val parts = mutableListOf<MutableList<SyncRecord>>(mutableListOf())
        var bytes = 0
        for (r in records) {
            val size = size(r)
            if (parts.last().isNotEmpty() && (parts.last().size >= maxRecords || bytes + size > maxBytes)) {
                parts.add(mutableListOf())
                bytes = 0
            }
            parts.last().add(r)
            bytes += size
        }
        return parts
    }

    fun size(record: SyncRecord): Int = WireJson.encodeToString(record).toByteArray().size

    /** A downloaded body; `records` stay raw JSON (unknown fields and types are rewritten untouched). */
    class Body(val json: JsonObject) {
        val raw: List<JsonElement> get() = (json["records"] as? JsonArray).orEmpty()
        val parts: Int get() = (json["parts"] as? JsonPrimitive)?.intOrNull ?: 1
        val covers: List<Cover>
            get() = (json["covers"] as? JsonArray).orEmpty().mapNotNull { c ->
                val o = c as? JsonObject ?: return@mapNotNull null
                val id = (o["fileId"] as? JsonPrimitive)?.content ?: return@mapNotNull null
                Cover(id, (o["name"] as? JsonPrimitive)?.content ?: "")
            }

        /** Envelopes that decode; a malformed one is skipped (it stays in the file). */
        fun records(): List<SyncRecord> = raw.mapNotNull { runCatching { WireJson.decode(it) }.getOrNull() }

        fun encode(): ByteArray = gzip(json)

        /**
         * Purge rewrite: without the envelopes owned by `owners` and the non-tombstone envelopes of those Entries; null when
         * nothing changes.
         */
        fun purged(owners: Set<ToriId>): Body? {
            val kept = raw.filterNot { e ->
                val o = e as? JsonObject ?: return@filterNot false
                val owner = id(o["owner"])
                val entry = id(o["id"])
                (owner != null && owner in owners) ||
                    ((o["type"] as? JsonPrimitive)?.content == "entry" && entry in owners && (o["deleted"] as? JsonPrimitive)?.booleanOrNull != true)
            }
            if (kept.size == raw.size) return null
            return Body(JsonObject(json + ("records" to JsonArray(kept))))
        }

        private fun id(e: JsonElement?): ToriId? = (e as? JsonPrimitive)?.takeIf { it.isString }?.content?.let(ToriId::parse)

        companion object {
            fun decode(bytes: ByteArray): Body = Body(WireJson.json.parseToJsonElement(String(gunzip(bytes))) as JsonObject)
        }
    }

    private fun props(kind: String, generation: String, deviceId: String, numberKey: String, number: String, part: Int) = mapOf(
        "layout" to "$LAYOUT", "generation" to generation, "kind" to kind, "deviceId" to deviceId, numberKey to number, "part" to "$part",
    )

    private fun body(props: Map<String, String>, parts: Int, covers: List<Cover>?, records: List<JsonElement>) = buildJsonObject {
        put("layout", LAYOUT)
        put("generation", props.getValue("generation"))
        put("kind", props.getValue("kind"))
        put("deviceId", props.getValue("deviceId"))
        props["seq"]?.let { put("seq", it.toLong()) }
        props["n"]?.let { put("n", it.toLong()) }
        put("part", props.getValue("part").toInt())
        put("parts", parts)
        if (covers != null) {
            put("covers", JsonArray(covers.map { buildJsonObject { put("fileId", it.fileId); put("name", it.name) } }))
        }
        put("records", JsonArray(records))
    }

    fun gzip(json: JsonObject): ByteArray = gzip(WireJson.json.encodeToString(JsonObject.serializer(), json).toByteArray())

    fun gzip(bytes: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        GZIPOutputStream(out).use { it.write(bytes) }
        return out.toByteArray()
    }

    fun gunzip(bytes: ByteArray): ByteArray = GZIPInputStream(bytes.inputStream()).use { it.readBytes() }
}

/** Typed view of a Drive file's `appProperties`. */
internal val DriveFile.kind: String? get() = appProperties["kind"]
internal val DriveFile.layout: Int get() = appProperties["layout"]?.toIntOrNull() ?: 0
internal val DriveFile.generation: String? get() = appProperties["generation"]
internal val DriveFile.deviceId: String? get() = appProperties["deviceId"]
internal val DriveFile.part: Int? get() = appProperties["part"]?.toIntOrNull()
internal val DriveFile.isRecordFile: Boolean get() = kind == DriveFormat.BATCH || kind == DriveFormat.SNAPSHOT
