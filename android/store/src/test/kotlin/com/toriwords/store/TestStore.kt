package com.toriwords.store

import androidx.test.core.app.ApplicationProvider
import com.toriwords.core.SyncRecord
import kotlinx.coroutines.runBlocking
import java.io.File
import java.nio.file.Files

/** 2025-11-10 12:00 UTC. */
const val T0 = 1_762_776_000_000L

class TestStore(now: Long = T0, launch: Boolean = true, file: Boolean = false) {
    var ms = now
    val dir: File = Files.createTempDirectory("store").toFile()
    val marker = File(dir, "device-marker")
    val name = "user-${System.nanoTime()}.sqlite"
    val store: ToriStore = if (file) {
        ToriStore.open(ApplicationProvider.getApplicationContext(), name) { ms }
    } else {
        ToriStore.inMemory(ApplicationProvider.getApplicationContext()) { ms }
    }

    init {
        if (launch) runBlocking { store.launch(marker, "Pixel") }
    }

    suspend fun activate(account: String = "account-1") = store.activateDrive(account)
    suspend fun rows(sql: String, vararg args: Any?): List<Row> = store.read { it.sql.rows(sql, *args) }
    suspend fun long(sql: String, vararg args: Any?): Long? = store.read { it.sql.long(sql, *args) }
    suspend fun text(sql: String, vararg args: Any?): String? = store.read { it.sql.text(sql, *args) }
    suspend fun records(): List<SyncRecord> = store.read { it.allRecords() }

    /** Logical content: synced state, derived columns and card caches (device rows excluded). */
    suspend fun dump(): List<String> = store.read { r ->
        RecordType.ALL.filter { it !== RecordType.DEVICE }.flatMap { type ->
            r.sql.rows("SELECT * FROM ${type.name} ORDER BY id").map { row ->
                type.name + " " + row.values.keys.sorted().joinToString(" ") { c ->
                    val v = row[c]
                    "$c=" + if (v is ByteArray) v.joinToString("") { "%02x".format(it) } else v.toString()
                }
            }
        }
    }
}

fun tr(t: String) = NewSense(translation = t, source = SenseSource.WIKTIONARY, dictVersion = "2026.11.1")
