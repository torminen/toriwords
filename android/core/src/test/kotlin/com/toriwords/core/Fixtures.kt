package com.toriwords.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import java.io.File

/** One case of a shared fixture file; `toString` is the case id, so test names print it. */
class FixtureCase(val file: JsonObject, val json: JsonObject) {
    operator fun get(key: String): JsonElement = json[key] ?: JsonNull
    fun has(key: String): Boolean = key in json
    override fun toString(): String = json.getValue("id").jsonPrimitive.content
}

/** Reads `spec/fixtures` in place; the path comes from the `fixturesDir` system property set by Gradle. */
object Fixtures {
    private val dir = File(System.getProperty("fixturesDir") ?: error("fixturesDir system property not set"))

    fun file(path: String): JsonObject = Json.parseToJsonElement(File(dir, path).readText()).jsonObject

    fun cases(vararg paths: String): List<FixtureCase> = paths.flatMap { path ->
        val f = file(path)
        val cases = f.getValue("cases").jsonArray.map { FixtureCase(f, it.jsonObject) }
        check(cases.isNotEmpty()) { "$path has no cases" }
        cases
    }
}

val JsonElement.str: String? get() = (this as? JsonPrimitive)?.takeIf { it.isString }?.content
val JsonElement.isNull: Boolean get() = this is JsonNull
val JsonElement.int: Int get() = jsonPrimitive.int
val JsonElement.intOrNull: Int? get() = if (this is JsonNull) null else jsonPrimitive.int
val JsonElement.long: Long get() = jsonPrimitive.long
val JsonElement.double: Double get() = jsonPrimitive.double
val JsonElement.bool: Boolean? get() = (this as? JsonPrimitive)?.booleanOrNull
val JsonElement.array: List<JsonElement> get() = if (this is JsonNull) emptyList() else jsonArray
operator fun JsonElement.get(key: String): JsonElement = (this as? JsonObject)?.get(key) ?: JsonNull
operator fun JsonElement.get(index: Int): JsonElement = (this as JsonArray)[index]

fun id(j: JsonElement): ToriId = ToriId.parse(j.str!!)!!
