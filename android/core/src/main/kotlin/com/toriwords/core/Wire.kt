package com.toriwords.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/**
 * A synced record as pushed, pulled, exported and restored. Values stay raw JSON so unknown fields (and numbers) round-trip
 * byte for byte (doc 38 §4.1); known columns map them in the store.
 */
typealias SyncRecord = Envelope<JsonElement>

/** Wire JSON of envelopes and field versions (doc 36 §11.1). */
object WireJson {
    val json = Json { explicitNulls = true }

    fun <V> field(f: FieldVersion<V>, value: (V) -> JsonElement): JsonObject = buildJsonObject {
        put("v", value(f.value))
        put("c", f.clock.toString())
        put("u", f.rank.wire)
    }

    fun <V> field(json: JsonElement, value: (JsonElement) -> V): FieldVersion<V> {
        val o = json.jsonObject
        return FieldVersion(
            value(o["v"] ?: JsonNull),
            HlcTimestamp.parse(o.getValue("c").jsonPrimitive.content) ?: throw IllegalArgumentException("bad clock"),
            AuthorRank.fromWire(o.getValue("u").jsonPrimitive.int) ?: throw IllegalArgumentException("bad rank"),
        )
    }

    /** Key order and explicit nulls as the iOS encoder: id, type, schema, owner, deleted, mergedInto, fields. */
    fun <V> envelope(e: Envelope<V>, value: (V) -> JsonElement): JsonObject = buildJsonObject {
        put("id", e.id.toString())
        put("type", e.type)
        put("schema", e.schema)
        put("owner", e.owner?.toString())
        put("deleted", e.deleted)
        put("mergedInto", e.mergedInto?.toString())
        put("fields", JsonObject(e.fields.mapValues { field(it.value, value) }))
    }

    fun <V> envelope(json: JsonElement, value: (JsonElement) -> V): Envelope<V> {
        val o = json.jsonObject
        fun id(key: String): ToriId? = (o[key] as? JsonPrimitive)?.takeIf { it.isString }?.let {
            ToriId.parse(it.content) ?: throw IllegalArgumentException("not a UUID: ${it.content}")
        }
        return Envelope(
            id = id("id") ?: throw IllegalArgumentException("missing id"),
            type = o.getValue("type").jsonPrimitive.content,
            schema = o.getValue("schema").jsonPrimitive.int,
            owner = id("owner"),
            deleted = (o["deleted"] as? JsonPrimitive)?.booleanOrNull ?: false,
            mergedInto = id("mergedInto"),
            fields = (o["fields"] as? JsonObject)?.mapValues { field(it.value, value) } ?: emptyMap(),
        )
    }

    fun encode(record: SyncRecord): JsonObject = envelope(record) { it }
    fun decode(json: JsonElement): SyncRecord = envelope(json) { it }
    fun encodeToString(record: SyncRecord): String = json.encodeToString(JsonObject.serializer(), encode(record))
    fun decodeFromString(text: String): SyncRecord = decode(json.parseToJsonElement(text))
}
