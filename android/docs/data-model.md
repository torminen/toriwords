# ToriWords for Android: data model and local storage

This file specifies the local database `user.sqlite`: its tables, columns, derived keys and migrations. It also covers per-device settings storage, OS backup, export and restore, and "Remove all data from this device". Domain concepts (Entry, Sense, Context, Card, ReviewLog, Tag, Source) are explained in [domain.md](domain.md). How records travel between devices is in [sync.md](sync.md). Card scheduling state is computed as described in [scheduler.md](scheduler.md).

## 1. Engine and conventions

- **Engine:** Room (KSP) on `BundledSQLiteDriver`. That gives the same SQLite version on every device, independent of the OS copy. Queries run on `Dispatchers.IO`. One database instance per process ([architecture.md](architecture.md#5-concurrency)).
- **Room mapping:** entities mirror the tables one to one. Complex reads (canonical joins, queue inputs, replay inputs, search) are explicit SQL in `@Query`/`@RawQuery`, not Room relations.
- **IDs:** 16-byte `BLOB` UUIDs, mapped to a Kotlin value class `RecordId(bytes: ByteArray)` with a type converter, value equality and an **unsigned** byte comparator. UUIDv7 for random IDs, UUIDv5 under the ToriWords namespace for deterministic IDs ([sync.md](sync.md)). Kotlin `Byte` is signed, so a naive comparison sorts `0x80…` before `0x7F…`. Every "smallest ID" rule (survivor choice, ties, sort keys) uses the unsigned comparator, or SQL `ORDER BY` on the BLOB (SQLite compares BLOBs with `memcmp`, which is unsigned). Pinned by `spec/fixtures/ids/byte-order.json`.
- **Instants:** `INTEGER` Unix milliseconds UTC. **Offsets:** `INTEGER` minutes east of UTC. **Days:** `INTEGER` day numbers; a day starts at 04:00 local time ([scheduler.md](scheduler.md)).
- **Enums:** `TEXT` with exactly the spellings in this file.
- **Booleans:** `INTEGER` 0/1 (sent as JSON `true`/`false` on the wire).
- **JSON columns** (`field_clocks`, `extra`, `fsrs_w`, some `sync_state` values) are written with kotlinx.serialization. `extra` keeps each unknown value as a raw `JsonElement`, so numbers and strings round-trip byte for byte.
- **Highlights:** `highlight_offset` / `highlight_length` are UTF-16 code units, which are Kotlin `String` indices directly. Capture length limits (500 and 5,000 characters) count Unicode code points instead.
- **Text order.** Both databases use `PRAGMA encoding = 'UTF-8'`; the app asserts it when it opens `user.sqlite`. Every order or prefix range that must match iOS is done in SQL with the default `BINARY` collation, which on UTF-8 is Unicode scalar order. That covers user `match_key` and `name_key` and dictionary `key` and `form_key` (Words A–Z, autocomplete, tag lists). Kotlin `String.compareTo` compares UTF-16 code units, which differs from that order for characters above U+FFFF and in U+E000–U+FFFF, so it is never used for these lists. Where an in-memory sort cannot be avoided, it compares UTF-8 bytes. `COLLATE NOCASE` and `LOCALIZED` are never used. Pinned by `spec/fixtures/normalization/text-order.json`.

### 1.1 Sync columns

Every **synced** table has these columns:

| Column | Type | Meaning |
|---|---|---|
| `field_clocks` | TEXT NOT NULL DEFAULT `'{}'` | JSON object: field name → `{"c": "<32-hex HLC>", "u": 0 or 1}`. The clock and author rank of the last write of that field. |
| `deleted` | INTEGER NOT NULL DEFAULT 0 | Terminal tombstone. |
| `merged_into` | BLOB NULL | Terminal redirect to the surviving duplicate. |
| `extra` | TEXT NULL | JSON object of fields this app version does not know, each as `{v, c, u}`. Kept, merged generically, sent back unchanged. |
| `schema` | INTEGER NOT NULL DEFAULT 1 | Payload schema version of the record ([sync.md](sync.md)). |

All other synced columns are **nullable**, so a tombstone can drop its field values. The owner column (`entry_id`, `owner_entry_id`) is kept on tombstones.

**Wire field names** are the synced column names in this file, exactly (snake_case). The envelope-level `id`, `deleted`, `merged_into`, `owner` and `schema` are not inside `fields`. Columns marked *local* are never synced; they are derived data or bookkeeping.

**Author rank `u`:** 1 for any change caused directly by a user action (typing, picking a suggestion, editing, exclude/resume, tagging/untagging, reordering Senses, deleting). 0 for everything automatic (enrichment fills, `enrichment_status`, setting and clearing `needs_check`, Card creation, `merged_into`, Device bookkeeping, defaults). "The user has edited this field" is simply `u = 1` in `field_clocks`; there is no separate flag. Write rules:
- One HLC stamp per write call.
- A no-op write (same value, rank not rising) creates no new clock and no outbox row.
- An automatic (rank 0) write never replaces a field whose current rank is 1.

## 2. One logical schema, per-platform transport tables

- **Shared with iOS:** every synced table and its columns, and the shared local tables `pending_changes`, `sync_state` (the shared keys) and `schema_meta`. Table names, column names, types, enum spellings and the meaning of every column are identical on both platforms. Local derived columns (`match_key`, `*_fold`, `canonical_*`, card cache, `review_day`) are also identical, because the shared fixtures exercise them.
- **Per platform:** sync-transport and extension bookkeeping.
  - Android has `drive_file` and `drive_file_owner`.
  - iOS has `cloud_record_meta` (CloudKit change tags) and `inbox_import` (Share Extension inbox). Android does **not** create these two tables.
- **`schema_meta.version` is per platform.** It counts Android's own migrations. No database file ever moves between iOS and Android. The cross-platform contracts are the per-record `schema` in the wire envelope and the backup file's `version` and `protocol` ([Export and restore](#9-export-and-restore)).

## 3. Synced tables

### 3.1 `language_pair`

One row in v1: Russian native, English target. ID `v5("pair:ru:en")`.

| Column | Type | Notes |
|---|---|---|
| `id` | BLOB PK | |
| `native_lang` | TEXT | BCP-47, `ru` |
| `target_lang` | TEXT | `en` |
| `created_at` | INTEGER | |

### 3.2 `entry`

One word or phrase.

| Column | Type | Notes |
|---|---|---|
| `id` | BLOB PK | UUIDv7 |
| `language_pair_id` | BLOB | no FK |
| `text` | TEXT | as written by the user or the dictionary; non-empty after trim |
| `ipa` | TEXT NULL | from Wiktionary or the user |
| `note` | TEXT NULL | |
| `status` | TEXT | `active` / `excluded` |
| `excluded_reason` | TEXT NULL | `known` / `paused` / NULL |
| `enrichment_status` | TEXT | `pending` / `done` / `unavailable` |
| `needs_check` | INTEGER | 0/1; set and cleared with rank 0 |
| `origin` | TEXT | `typed` (Add screen), `text_selection` (selection toolbar), `shared` (share sheet), `imported` (later) |
| `created_at` | INTEGER | display and sort only |
| `updated_at` | INTEGER | display and sort only; never used for conflicts |
| `match_key` | TEXT | *local*, match key of `text` |
| `text_fold` | TEXT | *local*, search fold of `text` |
| `canonical_id` | BLOB | *local*, end of the `merged_into` chain (self if none) |
| `enrich_attempts` | INTEGER NOT NULL DEFAULT 0 | *local*, machine-translation failures counted for the retry policy |

`kind` (word or phrase) is derived (text contains whitespace → phrase) and never stored.

### 3.3 `sense`

One meaning.

| Column | Type | Notes |
|---|---|---|
| `id` | BLOB PK | UUIDv7 when the user chose it; `v5("autosense:<entryId>:<ordinal>")` for automatic fills |
| `entry_id` | BLOB | owner |
| `translation` | TEXT NULL | Russian |
| `definition` | TEXT NULL | English |
| `part_of_speech` | TEXT NULL | |
| `position` | REAL | fractional index; ties broken by `id` |
| `translation_src`, `definition_src`, `pos_src` | TEXT NULL | `user` / `wiktionary` / `mt_mlkit` (Android machine translation) / `mt_apple` (written by iOS; kept as is) |
| `dict_version` | TEXT NULL | e.g. `2026.11.1` |
| `dict_headword_key` | TEXT NULL | |
| `dict_sense_ordinal` | INTEGER NULL | |
| `translation_fold`, `definition_fold` | TEXT NULL | *local*, search folds |
| `canonical_id`, `canonical_entry_id` | BLOB | *local* |

**Provenance of picked suggestions** (also in the Edit form): a Sense created from a dictionary or machine-translation suggestion stores the suggestion's `_src`, `dict_version`, `dict_headword_key` and `dict_sense_ordinal`, as long as the user did not change its translation, definition or part of speech before saving. If any of the three was edited, the Sense is saved as a user Sense: `_src = user` for the fields, no dictionary reference. The edit use case keeps the original suggestion beside the draft row and compares all three fields at save time.

### 3.4 `source`

| Column | Type | Notes |
|---|---|---|
| `id` | BLOB PK | `v5("source:<urlKey>")` when a URL exists, else UUIDv7 |
| `kind` | TEXT | `web` / `app` / `other` / `suggested` (an Entry added from a related-word suggestion; `title` = the headword it was suggested from) |
| `url` | TEXT NULL | |
| `title` | TEXT NULL | |
| `app` | TEXT NULL | Android: the user-visible label of the app that started the capture (for example "Chrome"), when Android reports the caller; NULL when the caller is unknown, is the system chooser or is ToriWords itself ([capture-and-enrichment.md](capture-and-enrichment.md)). iOS writes "Safari" or NULL. |
| `url_key` | TEXT NULL | *local*, URL key |
| `canonical_id` | BLOB | *local* |

### 3.5 `context`

One real sentence, or a **source-only** Context (`sentence` NULL) that records where an Entry came from when there is no sentence. That happens for a link-only share or a related-word add.

| Column | Type | Notes |
|---|---|---|
| `id` | BLOB PK | UUIDv7 |
| `entry_id` | BLOB | owner |
| `sense_id` | BLOB NULL | |
| `sentence` | TEXT NULL | ≤ 500 code points after the capture rules; NULL = source-only (then `source_id` is set) |
| `highlight_offset`, `highlight_length` | INTEGER NULL | UTF-16 code units; NULL when the sentence does not contain the Entry text, or is NULL |
| `source_id` | BLOB NULL | |
| `captured_at` | INTEGER | |
| `sentence_fold` | TEXT NULL | *local*, search fold |
| `canonical_id`, `canonical_entry_id` | BLOB | *local* |

### 3.6 `card`

Identity only; the scheduling state is a local cache.

| Column | Type | Notes |
|---|---|---|
| `id` | BLOB PK | `v5("card:<entryId>:<direction>")` |
| `entry_id` | BLOB | owner |
| `direction` | TEXT | `recognition` / `recall` / `cloze` |
| `import_ref` | TEXT NULL | later (Anki import) |
| `created_at` | INTEGER | |
| `stability`, `difficulty` | REAL | *local cache* |
| `last_review_day`, `due_day`, `reps`, `lapses` | INTEGER | *local cache* |
| `stage` | TEXT | *local cache*: `new` / `learning` / `known_well` |
| `params_id` | TEXT | *local cache* |
| `canonical_entry_id`, `canonical_card_id` | BLOB | *local*; `canonical_card_id = v5("card:<canonicalEntryId>:<direction>")` |

The cache is rebuilt by replaying the Card's logs ([scheduler.md](scheduler.md)). Cards are created with rank 0, for `recognition` and `recall`, when an Entry is canonical, live and `active` and has at least one live Sense with a non-empty translation. `cloze` Cards are created only for Entries with a Context that has a sentence and a highlight. Entries without a translation never appear in Review, the widget or Home due counts.

### 3.7 `review_log`

Append-only; synced columns are never updated after insert.

| Column | Type | Notes |
|---|---|---|
| `id` | BLOB PK | UUIDv7 |
| `card_id` | BLOB | never rewritten |
| `owner_entry_id` | BLOB | the envelope `owner`: the Card's Entry at write time (a Card ID cannot be inverted) |
| `reviewed_at` | INTEGER | device clock, stored as given |
| `utc_offset_min` | INTEGER | offset at answer time |
| `rating` | INTEGER NULL | FSRS 1–4; ToriWords writes 1 (Forgot) or 3 (Remembered); NULL only for imported non-answers |
| `answer_ms` | INTEGER NULL | time from card shown to answer, capped at 600,000 |
| `device_id` | BLOB | |
| `original_rating` | INTEGER NULL | imports only |
| `import_ref` | TEXT NULL | imports only |
| `review_day` | INTEGER | *local*, day number of `reviewed_at` in `utc_offset_min` |
| `review_type` | TEXT NULL | *local*; reserved, never filled (as on iOS) |
| `canonical_card_id` | BLOB | *local* |

### 3.8 `tag` and `entry_tag`

`tag`: `id` BLOB PK (UUIDv7), `name` TEXT; *local* `name_key` TEXT (tag key), `canonical_id` BLOB.

`entry_tag`: `id` BLOB PK = `v5("entrytag:<entryId>:<tagId>")`, `entry_id` BLOB (owner), `tag_id` BLOB, `present` INTEGER (0/1, last writer wins, rank 1 for user actions); *local* `canonical_entry_id`, `canonical_tag_id`. Links never get tombstones: untagging writes `present = 0`.

### 3.9 `settings`

One row, ID `v5("settings")`, created with rank 0 on first run.

| Column | Type | Default |
|---|---|---|
| `new_words_per_day` | INTEGER | 10 (range 0–50) |
| `desired_retention` | REAL | 0.90 (not shown in v1) |
| `fsrs_w` | TEXT | JSON array of 21 binary64 numbers, the FSRS-6 defaults ([scheduler.md](scheduler.md)) |
| `params_id` | TEXT | `fsrs6-default-1` |
| `scheduler_version` | INTEGER | 1 |

A change to `fsrs_w`, `desired_retention` or `scheduler_version` (local or pulled) triggers a full Card rebuild.

### 3.10 `device`

| Column | Type | Notes |
|---|---|---|
| `id` | BLOB PK | UUIDv7, new per installation and per restore |
| `platform` | TEXT | `android` (iOS writes `ios`) |
| `display_name` | TEXT | `Build.MODEL` (for example "Pixel 9"). Never the user-set device name, which may contain a person's name and would sync. |
| `first_seen` | INTEGER | |
| `is_this_device` | INTEGER NOT NULL DEFAULT 0 | *local* |

## 4. Local-only tables

### 4.1 Shared with iOS

| Table | Columns | Purpose |
|---|---|---|
| `pending_changes` | `record_id` BLOB NOT NULL, `type` TEXT NOT NULL, `field` TEXT NOT NULL, `clock` TEXT NOT NULL; PK `(record_id, field)` | The outbox. Upserted in the same transaction as every local write, **only while sync is active**. `field = '*'` means the whole record; envelope changes use `_deleted` and `_mergedInto`. `type` = the wire type, which is the table name. Rules: [sync.md](sync.md). |
| `sync_state` | `key` TEXT PK, `value` TEXT | Key/value bookkeeping, keys below. |
| `schema_meta` | `version` INTEGER NOT NULL | Android's local schema version ([Migrations](#7-migrations)). |

`sync_state` keys on Android:

| Key | Value | Shared with iOS |
|---|---|---|
| `hlc` | `{ms, counter}` of the hybrid logical clock, written in the same transaction as each write | yes |
| `lastServerTime` | latest Drive `modifiedTime` seen (Unix ms) | yes (meaning) |
| `lastSyncAt` | end of the last successful cycle (Unix ms) | yes |
| `excludedRecords` | `{appVersion, ids}`: records not uploaded (too large or rejected); cleared when the app version changes | yes |
| `driveAccount` | opaque hash of the authorized Google account; no email is stored. The outbox is active when it is set and `driveDeleted` is not. | Android |
| `pageToken` | Drive `changes.list` page token | Android |
| `generation`, `generationCreatedTime` | adopted `generation.json` UUID and its `createdTime` | Android |
| `driveDeleted` | `1` after the Drive data was deleted (outbox inactive until "Back up this device again") | Android |
| `deviceSeq` | last used batch file sequence number of this device | Android |
| `snapshotN` | last used snapshot number of this device | Android |

### 4.2 Android transport tables

The local index of the files in the Drive appDataFolder, used by compaction and purge ([sync.md](sync.md)). Filled on fetch, push, compaction and purge. Cleared, together with `pageToken`, on every fetch from a nil token, on restore and on Remove all data.

`drive_file`:

| Column | Type | Notes |
|---|---|---|
| `file_id` | TEXT PK | Drive fileId (file names are not unique on Drive) |
| `name` | TEXT | diagnostics only |
| `kind` | TEXT | `batch` / `snapshot` / `generation` |
| `device_id` | TEXT NULL | author device (from `appProperties`) |
| `layout` | INTEGER | file layout version |
| `generation` | TEXT NULL | generation the file was written for |
| `modified_time` | INTEGER | Drive `modifiedTime`, Unix ms |
| `applied` | INTEGER | 0/1: this device has applied the whole file |
| `has_unknown` | INTEGER | 0/1: holds records of unknown types; never covered by a snapshot or deleted |
| `pending_delete` | INTEGER | 0/1: covered by this device's snapshot, deletion still to do |

`drive_file_owner`: `file_id` TEXT (FK → `drive_file.file_id` `ON DELETE CASCADE`), `owner` BLOB (Entry ID: the envelope `owner`, or the Entry's own ID for Entry envelopes), `has_live` INTEGER (the file holds a non-tombstone envelope of that owner); PK `(file_id, owner)`, index `(owner)`.

## 5. Derived text keys and folds

Computed in `core`, stored in *local* columns in the same transaction as their source field (local write, applying a pulled record, restore, migration), and never synced. The exact character lists and corner cases are normative in `spec/fixtures/README.md` ("Rules for the text functions") and the `spec/fixtures/normalization/` cases. Summary:

- **Match key** (`entry.match_key`; also the *translation key* used to compare translations):
  1. Unicode NFC.
  2. Map apostrophe, quote and dash variants to `'`, `"` and `-`; map space separators to U+0020.
  3. Remove the listed default-ignorables.
  4. Lowercase per code point with the locale-free, context-free default mapping (Σ → σ always). Never `lowercase(Locale.getDefault())`. Kotlin `lowercase()` applies final sigma, so `core` maps per code point.
  5. Collapse and trim whitespace.
  6. Strip leading and trailing punctuation (P*) repeatedly, then trim again; symbols (S*) are kept.
  7. `ё` → `е`.

  An empty key means the caller rejects the text.
- **Sentence key:** steps 1–3, whitespace collapsed and trimmed, `ё/Ё` → `е/Е`; case and punctuation kept.
- **Tag key** (`tag.name_key`): NFC, the lowercase step, whitespace collapsed and trimmed, `ё` → `е`; punctuation kept (`C#` ≠ `C`); no quote mapping, no ignorable removal.
- **Search fold** (`*_fold` columns and the search query): steps 1–4, `ё` → `е`, whitespace collapsed and trimmed; punctuation and symbols kept. An empty fold column is stored as `''`, a NULL source gives NULL.
- **URL key** (`source.url_key`), only for `http`/`https` URLs:
  - an explicit split of scheme, userinfo, host, port, path, query and fragment, never a platform URL parser;
  - lowercase scheme and host; punycode per non-ASCII host label;
  - drop the default port and the fragment;
  - remove the `utm_*`, `fbclid`, `gclid`, `yclid` and `mc_eid` parameters (names case-sensitive) and keep the others in order; an empty query drops the `?`;
  - keep a trailing slash; `http` ≠ `https`.
- **Source key without URL:** match key of `title` + the app name as stored.

Kotlin specifics:
- NFC: `java.text.Normalizer`.
- Iterate by code point, never by `Char`.
- Punctuation: `Character.getType` in the seven P* categories.
- The quote, dash, space and ignorable maps are explicit code-point lists in `core`, not property lookups, so the JVM's and ART's Unicode tables cannot disagree on them.
- Fixtures use only characters whose categories are stable since Unicode 13 (Android 12). The instrumented run checks the device tables ([testing.md](testing.md)).

**Canonical IDs:** `canonical_id` = the end of the record's `merged_into` chain (itself if none). Children carry `canonical_entry_id` (and `canonical_card_id` / `canonical_tag_id`), recomputed when a parent arrives or merges ([sync.md](sync.md)).

## 6. Integrity rules

### 6.1 Indexes

As on iOS:
- `entry (language_pair_id, match_key)`, `entry (canonical_id)`, `entry (created_at)`, `entry (status)`;
- `sense (canonical_entry_id)`, `sense (entry_id)`;
- `context (canonical_entry_id)`, `context (entry_id)`;
- `card (due_day)`, `card (canonical_card_id)`, `card (canonical_entry_id)`, `card (entry_id)`;
- `review_log (canonical_card_id, reviewed_at, id)`, `review_log (review_day)`, `review_log (card_id)`, `review_log (owner_entry_id)`;
- `tag (name_key)`;
- `entry_tag (canonical_entry_id)`, `entry_tag (entry_id)`, `entry_tag (tag_id)`;
- `drive_file_owner (owner)`.

### 6.2 Unique keys are not constraints

"At most one live Entry per match key" (and one Source per URL key, one Tag per tag key) cannot be a `UNIQUE` index, because sync legitimately delivers duplicates from other devices. None of these indexes is `UNIQUE`. The deterministic duplicate merge ([sync.md](sync.md)) runs after each pull and after local edits that change a natural key.

### 6.3 Foreign keys and orphans

- **No FK constraints between synced records** (`entry_id`, `card_id`, `sense_id`, `source_id`, `tag_id`, `language_pair_id`, `merged_into`, `owner_entry_id`). They are plain indexed columns. FK constraints exist only between local-only tables (`drive_file_owner` → `drive_file`).
- Reason: pulled files arrive in Drive change order, not parent first, and each chunk is its own transaction. A child may be committed before its parent.
- **Orphan rule:** a row whose parent (Entry, Card, Tag, Source, merge survivor) is not present locally is stored as is. It is **hidden** from the UI, the queue and stats, and **excluded from replay**. Every read reaches children through joins on the live canonical parent, so orphans drop out without flags.
- **When the parent arrives**, in the same transaction that applies it: recompute the children's derived columns (`canonical_*`, `review_day`), then replay the affected Cards. The result equals receiving everything at once.

### 6.4 Deletion

Deletion is logical first. A tombstone on the Entry hides its children through the same joins. Children are then purged with one `DELETE` per child table by `canonical_entry_id` / `owner_entry_id` (never `ON DELETE CASCADE`):
- while sync is inactive: immediately;
- while sync is active: when the Entry tombstone has been uploaded, followed by the cloud purge ([sync.md](sync.md)).

The purge covers the whole merge group. A deletion with Undo is held in memory during the Undo snackbar. The tombstone is written when the snackbar closes, at the next deletion, or when the app goes to the background ([architecture.md](architecture.md#10-background-work-and-entry-points)).

## 7. Migrations

- Hand-written, numbered, forward-only Room `Migration` objects. No `AutoMigration`, so every schema step is explicit and reviewable. Room's schema JSON is exported to `store/schemas/` and committed.
- Room's `version` and `schema_meta.version` are the same number: Android's local schema version, written by every migration. Version 1 is the schema in this file.
- Migrations run on first database access in the process. Every entry point reaches that through `AppReady.await()` ([architecture.md](architecture.md#7-start-up-first-run-restore-and-reinstall)) before reading data, before capture lookups and before sync. All entry points share one process, so no reader can see a half-migrated schema.
- **Additive changes are the norm** (new nullable column, new table). Renames and drops: add the new column, copy, stop reading the old one, drop it in a later release.
- **Synced shape changes are coordinated with iOS.** A new synced column or record type is introduced on both platforms, with the same name, type and per-record `schema` bump. Fields this version does not know live in `extra`; unknown record types are skipped on pull ([sync.md](sync.md)). No migration ever requires a full re-upload.
- **Derived columns follow their rule.** A change to a shared text rule that feeds a stored column (match key, tag key, URL key, search fold) is a migration. It recomputes every affected column (`match_key`, `name_key`, `url_key`, `*_fold`) and then runs the duplicate merge. Otherwise iOS and Android results drift for existing rows.
- **Tests:** `MigrationTestHelper` migrates a fixture database of every historical Android version to the current one and checks identical logical content ([testing.md](testing.md)).

## 8. Settings storage

### 8.1 Synced versus per-device

| Synced (`settings` record) | Per device (DataStore, never synced) |
|---|---|
| New words per day; desired retention; FSRS parameter set (`fsrs_w`, `params_id`); scheduler version. | Everything in the per-device DataStore below. |

The review-day start (04:00) is a constant, not a setting. The app language is stored by the system (Android 13+) or by AppCompat (Android 12), not by ToriWords ([architecture.md](architecture.md#12-app-language)).

### 8.2 Per-device settings DataStore

File `device_settings` (Preferences DataStore). Included in OS backup.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `reminderEnabled` | Boolean | false | Daily reminder on/off |
| `reminderMinutes` | Int | 1140 (19:00) | Reminder time, minutes after local midnight |
| `accent` | String | `us` | Pronunciation accent: `us` / `uk` |
| `autoPlayOnReveal` | Boolean | false | Speak the word when the card is revealed |
| `swipeDemoShown` | Boolean | false | The Review swipe demo was shown |
| `reminderOfferShown` | Boolean | false | The one-time reminder offer after the first finished session was shown |
| `widgetHintSnoozedUntil` | Long | 0 | Epoch seconds; the Add screen's widget hint stays hidden until then ("Not now" sets now + 24 h) |
| `dictionarySha256` | String | — | SHA-256 of the installed dictionary copy |
| `dictionaryVersion` | String | — | Last seen dictionary version; a change re-runs enrichment on `unavailable` Entries |

There is no selection-menu tip and no share-menu tip flag on Android. The Add screen's first-run hint is not persisted.

### 8.3 Sticky capture fields

File `capture_sticky` (Preferences DataStore). Excluded from backup.

| Key | Type | Meaning |
|---|---|---|
| `updatedAt` | Long | Unix ms of the last Save in the capture sheet |
| `sourceTitle` | String (absent = none) | Last used source title |
| `tags` | String | JSON array of tag names, in the order shown |

Offered again for **30 minutes** after `updatedAt`. Written and read **only by the capture sheet**; the Add screen does not pre-fill from them ([capture-and-enrichment.md](capture-and-enrichment.md)).

## 9. Export and restore

### 9.1 Formats

**JSON backup** (restorable). File name `ToriWords-backup-YYYY-MM-DD.json`, dated in the device's time zone, MIME `application/json`:

```json
{
  "format": "toriwords-backup",
  "version": 1,
  "exportedAt": "2026-11-27T10:15:00Z",
  "protocol": 1,
  "attribution": "<Wiktionary attribution text>",
  "records": [ { "id": "…", "type": "entry", "schema": 1, "owner": null, "deleted": false, "mergedInto": null, "fields": { } } ]
}
```

- `records` holds every **live** synced record as a full sync envelope, with field clocks and ranks (envelope format: [sync.md](sync.md)). Tombstones are not exported.
- `version` is the backup file format version; `protocol` is the record envelope protocol.
- `attribution` is the dictionary's licence text (`meta.licence_text` of the installed dictionary, else the built-in default text).
- The file is the same on iOS and Android. A file from either platform restores on the other; this is the only way to move words between them.

**CSV** (lossy, not a backup). File name `ToriWords-YYYY-MM-DD.csv`, MIME `text/csv`. UTF-8, RFC 4180, CRLF line ends. Fields containing `,`, `"`, CR or LF are quoted, with `"` doubled.
- Header row: `text,translations,definitions,sentence,source,tags,stage,created`.
- One row per live canonical Entry, sorted A–Z by match key:

| Column | Value |
|---|---|
| `text` | Entry text |
| `translations` | non-empty translations of live Senses in display order, joined with `"; "` |
| `definitions` | non-empty definitions, same order and separator |
| `sentence` | the sentence of the first live Context by (`captured_at`, `id`); empty if none |
| `source` | that Context's canonical Source `title`, else its `url`, else empty |
| `tags` | tag names joined with `"; "` |
| `stage` | `needsTranslation` / `new` / `learning` / `knownWell` / `known` / `paused` |
| `created` | `YYYY-MM-DD` of the review day of `created_at` in the current offset |

- **Attribution row:** only when the exported data contains Wiktionary-derived text, the file ends with one extra row holding a single field, the attribution text. Wiktionary-derived means some live Sense of a live Entry has `wiktionary` in `translation_src`, `definition_src` or `pos_src`. Without such text, there is no attribution row.

### 9.2 Export

Settings → Data → Export, offline, no Drive needed. Disabled with a note when the vocabulary is empty. The file is built in the application scope with progress and cancel, streamed and never held whole in memory. Two destinations:
- **Share:** written to `cacheDir/exports/<name>` and offered with `Intent.ACTION_SEND` through a `FileProvider` content URI (`FLAG_GRANT_READ_URI_PERMISSION`) in the system share sheet. Old export files are deleted at the next export and when the cache is trimmed.
- **Save to device:** `Intent.ACTION_CREATE_DOCUMENT` (Storage Access Framework) with the proposed file name and MIME type. The export streams directly into the returned URI. No storage permission. Cancelling the picker does nothing.

### 9.3 Restore

Settings → Data → Restore from backup. `Intent.ACTION_OPEN_DOCUMENT` with MIME types `application/json` and `*/*` (many providers mislabel JSON); no storage permission.

1. **Validate the header:** if `format` ≠ `toriwords-backup`, or `version`/`protocol` are missing → "This is not a ToriWords backup", nothing changes. If `version` or `protocol` is higher than the app supports (both 1 in v1) → "Update the app", nothing changes.
2. **Pre-sync:** if sync is active, run one sync cycle first, so Entries deleted on other devices are local tombstones. If that cycle fails or sync is inactive, restore runs against local tombstones only. An Entry deleted elsewhere but not yet fetched is then counted as imported and disappears at the next sync (delete wins).
3. **Apply:** parse the file as a stream (kotlinx.serialization `decodeToSequence` over `records`) and apply the records **as if pulled** ([sync.md](sync.md)), in pages of 1,000 records, one transaction each. Unknown fields are kept in `extra`. While sync is active, each inserted or updated record gets a `*` outbox row. Records whose Entry is tombstoned locally are not restored.
4. **Then:** duplicate merge, replay, and one more sync cycle if sync is active.
5. **Summary counts:**
   - imported = new canonical Entry IDs;
   - merged = new Entry IDs that merged into an existing Entry;
   - deleted earlier = Entry IDs tombstoned locally and therefore not restored.

Restoring the same file twice changes nothing.

## 10. OS backup

`res/xml/data_extraction_rules.xml`:

| Section | Include | Exclude |
|---|---|---|
| `cloud-backup` | `database/user.sqlite`, `database/user.sqlite-wal`; `file/datastore/device_settings.preferences_pb` | everything under `no_backup/` (implicit), `file/datastore/capture_sticky.preferences_pb`, `cache/` |
| `device-transfer` | same as cloud | same as cloud, **plus** an explicit exclude of `no_backup/device-marker` |

- `user.sqlite` is backed up as is (checkpointed on `ON_STOP`, [architecture.md](architecture.md#6-files-on-the-device)).
- Android's Auto Backup quota is **25 MB per app**. Above it, cloud backup silently stops. This is accepted for v1; a smaller backup copy is a later item.
- A restored database is detected by the missing or different `device-marker` and handled at start-up: new Device ID, Drive bookkeeping reset, everything marked pending ([architecture.md](architecture.md#7-start-up-first-run-restore-and-reinstall)).

## 11. Remove all data from this device

Settings → Data → Remove all data from this device. The app first warns about unsynced changes. While sync is active the warning adds that the words stay in Google Drive and come back at the next sync, and that "Delete Drive data" removes them everywhere. Wording: [copy.md](copy.md).

In one transaction:
- delete all rows of every synced table **except `device`** (all Device rows are kept, including this device's);
- delete all of `pending_changes`;
- recreate the LanguagePair and Settings defaults (rank 0);
- clear `pageToken`, `generation`, `generationCreatedTime`, `deviceSeq` and `snapshotN`, and delete all `drive_file` and `drive_file_owner` rows.

Kept: `driveAccount`, `driveDeleted`, `hlc`, the per-device DataStore and the installed dictionary. If sync is on, the next cycle downloads everything Drive still has. Afterwards the app rewrites the widget snapshot and re-arms the reminder.

## 12. Expected size

10,000 Entries, 30,000 Senses and Contexts, 20,000 Cards and 300,000 ReviewLogs take roughly 30–60 MB with indexes (to be measured). Well within device limits, but above the Auto Backup quota at the upper end ([OS backup](#10-os-backup)).
