@file:Suppress("PropertyName", "ArrayInDataClass")

package com.toriwords.store

import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Embedded
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.RoomDatabase
import androidx.room.Transaction
import androidx.room.Upsert
import androidx.sqlite.SQLiteConnection
import androidx.sqlite.execSQL

/*
 * `user.sqlite`, logical schema = doc 36 §4.1–§4.2 exactly (doc 38 §4.1), plus the local Drive file index (doc 38 §11.2).
 * The entities only declare the schema; reads and writes are explicit SQL (`Sql`), as doc 38 §4.1 asks for complex reads.
 * Synced columns are nullable so a tombstone can drop field values. No FK constraints between synced records (§4.3).
 */

/** Sync columns of every synced table. */
class SyncColumns(
    @ColumnInfo(defaultValue = "{}") val field_clocks: String,
    @ColumnInfo(defaultValue = "0") val deleted: Int,
    val merged_into: ByteArray?,
    val extra: String?,
    @ColumnInfo(defaultValue = "1") val schema: Int,
)

@Entity(tableName = "language_pair")
class LanguagePairRow(
    @PrimaryKey val id: ByteArray, val native_lang: String?, val target_lang: String?, val created_at: Long?,
    @Embedded val sync: SyncColumns,
)

@Entity(
    tableName = "entry",
    indices = [
        Index(name = "entry_key", value = ["language_pair_id", "match_key"]), Index(name = "entry_canonical", value = ["canonical_id"]),
        Index(name = "entry_created", value = ["created_at"]), Index(name = "entry_status", value = ["status"]),
    ],
)
class EntryRow(
    @PrimaryKey val id: ByteArray, val language_pair_id: ByteArray?, val text: String?, val ipa: String?, val note: String?,
    val status: String?, val excluded_reason: String?, val enrichment_status: String?, val needs_check: Int?, val origin: String?,
    val created_at: Long?, val updated_at: Long?, val match_key: String?, val text_fold: String?, val canonical_id: ByteArray?,
    @ColumnInfo(defaultValue = "0") val enrich_attempts: Int,
    @Embedded val sync: SyncColumns,
)

@Entity(
    tableName = "sense",
    indices = [Index(name = "sense_entry", value = ["canonical_entry_id"]), Index(name = "sense_owner", value = ["entry_id"])],
)
class SenseRow(
    @PrimaryKey val id: ByteArray, val entry_id: ByteArray?, val translation: String?, val definition: String?,
    val part_of_speech: String?, val position: Double?, val translation_src: String?, val definition_src: String?,
    val pos_src: String?, val dict_version: String?, val dict_headword_key: String?, val dict_sense_ordinal: Long?,
    val translation_fold: String?, val definition_fold: String?, val canonical_id: ByteArray?, val canonical_entry_id: ByteArray?,
    @Embedded val sync: SyncColumns,
)

@Entity(tableName = "source")
class SourceRow(
    @PrimaryKey val id: ByteArray, val kind: String?, val url: String?, val title: String?, val app: String?, val url_key: String?,
    val canonical_id: ByteArray?,
    @Embedded val sync: SyncColumns,
)

@Entity(
    tableName = "context",
    indices = [Index(name = "context_entry", value = ["canonical_entry_id"]), Index(name = "context_owner", value = ["entry_id"])],
)
class ContextRow(
    @PrimaryKey val id: ByteArray, val entry_id: ByteArray?, val sense_id: ByteArray?, val sentence: String?,
    val highlight_offset: Long?, val highlight_length: Long?, val source_id: ByteArray?, val captured_at: Long?,
    val sentence_fold: String?, val canonical_id: ByteArray?, val canonical_entry_id: ByteArray?,
    @Embedded val sync: SyncColumns,
)

@Entity(
    tableName = "card",
    indices = [
        Index(name = "card_due", value = ["due_day"]), Index(name = "card_canonical", value = ["canonical_card_id"]),
        Index(name = "card_entry", value = ["canonical_entry_id"]), Index(name = "card_owner", value = ["entry_id"]),
    ],
)
class CardRow(
    @PrimaryKey val id: ByteArray, val entry_id: ByteArray?, val direction: String?, val import_ref: String?, val created_at: Long?,
    val stability: Double?, val difficulty: Double?, val last_review_day: Long?, val due_day: Long?, val reps: Long?,
    val lapses: Long?, val stage: String?, val params_id: String?, val canonical_entry_id: ByteArray?,
    val canonical_card_id: ByteArray?,
    @Embedded val sync: SyncColumns,
)

@Entity(
    tableName = "review_log",
    indices = [
        Index(name = "review_log_card", value = ["canonical_card_id", "reviewed_at", "id"]),
        Index(name = "review_log_day", value = ["review_day"]), Index(name = "review_log_raw_card", value = ["card_id"]),
        Index(name = "review_log_owner", value = ["owner_entry_id"]),
    ],
)
class ReviewLogRow(
    @PrimaryKey val id: ByteArray, val card_id: ByteArray?, val owner_entry_id: ByteArray?, val reviewed_at: Long?,
    val utc_offset_min: Long?, val rating: Long?, val answer_ms: Long?, val device_id: ByteArray?, val original_rating: Long?,
    val import_ref: String?, val review_day: Long?, val review_type: String?, val canonical_card_id: ByteArray?,
    @Embedded val sync: SyncColumns,
)

@Entity(tableName = "tag", indices = [Index(name = "tag_key", value = ["name_key"])])
class TagRowEntity(
    @PrimaryKey val id: ByteArray, val name: String?, val name_key: String?, val canonical_id: ByteArray?,
    @Embedded val sync: SyncColumns,
)

@Entity(
    tableName = "entry_tag",
    indices = [
        Index(name = "entry_tag_entry", value = ["canonical_entry_id"]), Index(name = "entry_tag_owner", value = ["entry_id"]),
        Index(name = "entry_tag_tag", value = ["tag_id"]),
    ],
)
class EntryTagRow(
    @PrimaryKey val id: ByteArray, val entry_id: ByteArray?, val tag_id: ByteArray?, val present: Int?,
    val canonical_entry_id: ByteArray?, val canonical_tag_id: ByteArray?,
    @Embedded val sync: SyncColumns,
)

@Entity(tableName = "settings")
class SettingsRow(
    @PrimaryKey val id: ByteArray, val new_words_per_day: Long?, val desired_retention: Double?, val fsrs_w: String?,
    val params_id: String?, val scheduler_version: Long?,
    @Embedded val sync: SyncColumns,
)

@Entity(tableName = "device")
class DeviceRow(
    @PrimaryKey val id: ByteArray, val platform: String?, val display_name: String?, val first_seen: Long?,
    @ColumnInfo(defaultValue = "0") val is_this_device: Int,
    @Embedded val sync: SyncColumns,
)

/** The outbox (doc 36 §11.4). `field = '*'` = whole record; `_deleted` / `_mergedInto` envelope changes; `_cloudDelete` purge. */
@Entity(tableName = "pending_changes", primaryKeys = ["record_id", "field"])
class PendingChangeRow(val record_id: ByteArray, val type: String, val field: String, val clock: String)

@Entity(tableName = "sync_state")
class SyncStateRow(@PrimaryKey val key: String, val value: String?)

/** Exists for the shared logical schema; never written on Android (doc 38 §4.2). */
@Entity(tableName = "inbox_import")
class InboxImportRow(@PrimaryKey val inbox_id: ByteArray, val imported_at: Long)

@Entity(tableName = "schema_meta")
class SchemaMetaRow(@PrimaryKey(autoGenerate = false) val version: Int)

/** One file in Drive `appDataFolder`, as indexed locally (doc 38 §11.2). Local only, never synced. */
@Entity(tableName = "drive_file")
data class DriveFile(
    @PrimaryKey val file_id: String,
    val name: String,
    /** `batch` / `snapshot` / `generation`. */
    val kind: String,
    val device_id: String?,
    val layout: Int,
    val generation: String?,
    val modified_time: Long,
    /** The file's content was fully applied locally (it may go into a snapshot's `covers`). */
    @ColumnInfo(defaultValue = "0") val applied: Boolean = false,
    /** Holds records of unknown types: never covered, never deleted. */
    @ColumnInfo(defaultValue = "0") val has_unknown: Boolean = false,
    /** Covered by this device's snapshot; delete still to be done. */
    @ColumnInfo(defaultValue = "0") val pending_delete: Boolean = false,
)

/** Owners (Entry IDs) whose envelopes a file holds; `has_live` = a non-tombstone envelope of that owner is in it. */
@Entity(tableName = "drive_file_owner", primaryKeys = ["file_id", "owner"], indices = [Index(name = "drive_file_owner_owner", value = ["owner"])])
data class DriveFileOwner(val file_id: String, val owner: ByteArray, val has_live: Boolean) {
    companion object {
        /**
         * The owner index of one file: children by envelope `owner`, Entries under their own ID (doc 38 §11.2 Purge).
         * Records without an owner (Tags, Sources, …) are not indexed.
         */
        fun of(fileId: String, records: List<com.toriwords.core.SyncRecord>): List<DriveFileOwner> {
            val live = LinkedHashMap<com.toriwords.core.ToriId, Boolean>()
            for (r in records) {
                val owner = r.owner ?: r.id.takeIf { r.type == RecordType.ENTRY.name } ?: continue
                live[owner] = (live[owner] ?: false) || !r.deleted
            }
            return live.entries.sortedBy { it.key }.map { DriveFileOwner(fileId, it.key.bytes, it.value) }
        }
    }
}

@Dao
abstract class DriveFileDao {
    @Upsert abstract suspend fun upsert(files: List<DriveFile>)

    @Query("SELECT * FROM drive_file WHERE file_id = :fileId") abstract suspend fun file(fileId: String): DriveFile?

    @Query("SELECT * FROM drive_file ORDER BY file_id") abstract suspend fun all(): List<DriveFile>

    @Query("SELECT * FROM drive_file WHERE pending_delete = 1 ORDER BY file_id") abstract suspend fun pendingDeletes(): List<DriveFile>

    @Query("UPDATE drive_file SET pending_delete = 1 WHERE file_id IN (:fileIds)") abstract suspend fun markPendingDelete(fileIds: List<String>)

    /** Indexed files whose owners are not known yet (skipped on a nil-token fetch); a purge downloads them first. */
    @Query(
        "SELECT * FROM drive_file f WHERE f.kind <> 'generation' AND f.applied = 0 " +
            "AND NOT EXISTS (SELECT 1 FROM drive_file_owner o WHERE o.file_id = f.file_id) ORDER BY f.file_id",
    )
    abstract suspend fun filesWithUnknownOwners(): List<DriveFile>

    @Query("SELECT * FROM drive_file_owner WHERE file_id = :fileId ORDER BY owner") abstract suspend fun owners(fileId: String): List<DriveFileOwner>

    /** Files holding envelopes of any of these owners (purge candidates). */
    @Query("SELECT DISTINCT file_id FROM drive_file_owner WHERE owner IN (:owners) ORDER BY file_id")
    abstract suspend fun filesHolding(owners: List<ByteArray>): List<String>

    @Transaction
    open suspend fun replaceOwners(fileId: String, owners: List<DriveFileOwner>) {
        deleteOwners(listOf(fileId))
        insertOwners(owners)
    }

    @Transaction
    open suspend fun delete(fileIds: List<String>) {
        deleteOwners(fileIds)
        deleteFiles(fileIds)
    }

    @Upsert protected abstract suspend fun insertOwners(owners: List<DriveFileOwner>)

    @Query("DELETE FROM drive_file_owner WHERE file_id IN (:fileIds)") protected abstract suspend fun deleteOwners(fileIds: List<String>)

    @Query("DELETE FROM drive_file WHERE file_id IN (:fileIds)") protected abstract suspend fun deleteFiles(fileIds: List<String>)
}

@Database(
    entities = [
        LanguagePairRow::class, EntryRow::class, SenseRow::class, SourceRow::class, ContextRow::class, CardRow::class,
        ReviewLogRow::class, TagRowEntity::class, EntryTagRow::class, SettingsRow::class, DeviceRow::class,
        PendingChangeRow::class, SyncStateRow::class, InboxImportRow::class, SchemaMetaRow::class, DriveFile::class,
        DriveFileOwner::class,
    ],
    version = 1,
)
abstract class ToriDatabase : RoomDatabase() {
    abstract fun driveFiles(): DriveFileDao

    /** Logical schema version (`schema_meta.version`), shared with iOS (doc 36 §4.6); Room's own version is Android-internal. */
    internal object Create : Callback() {
        override fun onCreate(connection: SQLiteConnection) {
            connection.execSQL("INSERT INTO schema_meta (version) VALUES ($LOGICAL_SCHEMA_VERSION)")
        }

        // WAL and UTF-8 are Room/SQLite defaults; no foreign keys exist (explicit purge, doc 36 §4.3).
        override fun onOpen(connection: SQLiteConnection) {
            connection.execSQL("PRAGMA synchronous = NORMAL")
        }
    }

    companion object {
        const val LOGICAL_SCHEMA_VERSION = 1
    }
}
