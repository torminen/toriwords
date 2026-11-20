package com.toriwords.store

import com.toriwords.core.AuthorRank
import com.toriwords.core.FsrsParameters
import com.toriwords.core.ToriId
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import java.io.File

enum class LaunchOutcome { EXISTING, FRESH_INSTALL, RESTORED_FROM_BACKUP }

/**
 * Launch: fresh install or restored-from-backup handling. `deviceMarker` lives in `noBackupFilesDir`, so a restored
 * database without its marker is detected.
 */
suspend fun ToriStore.launch(deviceMarker: File, displayName: String): LaunchOutcome {
    val marker = runCatching { deviceMarker.readBytes() }.getOrNull()?.takeIf { it.size == 16 }?.let(ToriId::fromBytes)
    val outcome = write { tx ->
        val current = tx.sql.id("SELECT id FROM device WHERE is_this_device = 1")
        if (current != null && current == marker) return@write LaunchOutcome.EXISTING
        val device = tx.newId()
        tx.sql.exec("UPDATE device SET is_this_device = 0")
        tx.sql.exec("INSERT INTO device (id, is_this_device) VALUES (?, 1)", device)
        tx.node = device.high
        tx.set(
            RecordType.DEVICE, device,
            mapOf("platform" to JsonPrimitive("android"), "display_name" to JsonPrimitive(displayName), "first_seen" to tx.now.wire()),
            AuthorRank.AUTOMATIC,
        )
        if (current != null) {
            // Restored from a device backup: token and index are an older snapshot than Drive.
            Account.restoreReset(tx)
            return@write LaunchOutcome.RESTORED_FROM_BACKUP
        }
        Defaults.create(tx)
        LaunchOutcome.FRESH_INSTALL
    }
    thisDeviceId()?.let { id ->
        deviceMarker.parentFile?.mkdirs()
        val tmp = File(deviceMarker.path + ".tmp")
        tmp.writeBytes(id.bytes)
        tmp.renameTo(deviceMarker)
    }
    return outcome
}

/** The Device ID of this installation. */
suspend fun ToriStore.thisDeviceId(): ToriId? = read { it.sql.id("SELECT id FROM device WHERE is_this_device = 1") }

/** Settings → Data → "Remove all data from this device": user records deleted, defaults recreated, token and index gone. */
suspend fun ToriStore.removeAllDataFromDevice() = write { Account.deleteUserRecords(it) }

internal object Defaults {
    val pair = ToriId.languagePair("ru", "en")

    /** LanguagePair and Settings defaults, rank 0, deterministic IDs. */
    suspend fun create(tx: Tx) {
        tx.set(
            RecordType.LANGUAGE_PAIR, pair,
            mapOf("native_lang" to JsonPrimitive("ru"), "target_lang" to JsonPrimitive("en"), "created_at" to tx.now.wire()), AuthorRank.AUTOMATIC,
        )
        val p = FsrsParameters.DEFAULT
        tx.set(
            RecordType.SETTINGS, ToriId.settings,
            mapOf(
                "new_words_per_day" to 10L.wire(), "desired_retention" to FieldKind.jsonNumber(p.desiredRetention),
                "fsrs_w" to JsonArray(p.w.map(FieldKind::jsonNumber)), "params_id" to JsonPrimitive(Replay.DEFAULT_PARAMS_ID),
                "scheduler_version" to 1L.wire(),
            ),
            AuthorRank.AUTOMATIC,
        )
    }
}

internal object Account {
    suspend fun deleteUserRecords(tx: Tx) {
        for (type in RecordType.ALL) if (type !== RecordType.DEVICE) tx.sql.exec("DELETE FROM ${type.name}")
        Defaults.create(tx)
        tx.sql.exec("DELETE FROM pending_changes")
        SyncStateStore.reset(tx.sql)
    }

    /** Restored install: token and index cleared, every record pending; `driveDeleted` untouched. */
    suspend fun restoreReset(tx: Tx) {
        SyncStateStore.reset(tx.sql)
        Outbox.markAll(tx)
    }
}
