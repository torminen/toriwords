# ToriWords for iOS: data model and local storage

This file specifies the local database `user.sqlite`: its tables, columns, derived keys and migrations. It also covers per-device settings storage, OS backup, export and restore, and "Remove all data from this device". Domain concepts (Entry, Sense, Context, Card, ReviewLog, Tag, Source) are explained in [domain.md](domain.md). How records travel between devices is in [sync.md](sync.md). Card scheduling state is computed as described in [scheduler.md](scheduler.md).

**Code:** `ios/ToriKit/Sources/ToriStore` (`Schema.swift`, `Records.swift`, `Tx.swift`, `Maintenance.swift`, `Queries.swift`, `Backup.swift`, `ExportFile.swift`, `Launch.swift`, `ToriStore.swift`); text keys in `ios/ToriKit/Sources/ToriCore` (`TextKeys.swift`, `URLKey.swift`).

## 1. Engine and conventions

- **Engine:** GRDB `DatabasePool` over the system SQLite. One `ToriStore` per process owns `user.sqlite` in the app's Application Support directory ([architecture.md](architecture.md)). The Share Extension and the widget never open it.
- **Pragmas:** `journal_mode = WAL` (the pool's mode), `synchronous = NORMAL` (set on every connection), `foreign_keys = ON` (GRDB's default), `encoding = 'UTF-8'` (SQLite's default, fixed before the first table exists). The test `migrationsAndPragmas` checks all four. On every move to the background the app runs `PRAGMA wal_checkpoint(TRUNCATE)`.
- **Writes:** every write goes through `ToriStore.write`: one transaction that stamps clocks, fills the outbox and runs the post-write maintenance (canonical IDs, duplicate merge, Card creation, replay, purge) before commit ([sync.md](sync.md#applying-pulled-records-one-transaction-per-page)). Reads use `StoreReader` and GRDB `ValueObservation`.
- **Record mapping:** no ORM. `Records.swift` lists each synced table's fields with a kind (text, int, real, bool, id, json) and converts rows to and from envelopes. Complex reads (canonical joins, queue inputs, replay inputs, search) are explicit SQL.
- **IDs:** 16-byte `BLOB` UUIDs, mapped to the `ToriID` struct (two big-endian `UInt64` halves, `high` and `low`) with value equality and an **unsigned** comparator. UUIDv7 for random IDs, UUIDv5 under the ToriWords namespace for deterministic IDs ([sync.md](sync.md)). Every "smallest ID" rule (survivor choice, ties, sort keys) uses that comparator, or SQL `ORDER BY` on the BLOB (SQLite compares BLOBs with `memcmp`, which is unsigned). Pinned by `fixtures/ids/byte-order.json`.
- **Instants:** `INTEGER` Unix milliseconds UTC. **Offsets:** `INTEGER` minutes east of UTC. **Days:** `INTEGER` day numbers; a day starts at 04:00 local time ([scheduler.md](scheduler.md)).
- **Enums:** `TEXT` with exactly the spellings in this file.
- **Booleans:** `INTEGER` 0/1 (sent as JSON `true`/`false` on the wire).
- **JSON columns** (`field_clocks`, `extra`, `fsrs_w`, some `sync_state` values) are written with `JSONEncoder`. `extra` keeps each unknown field as a full `{v, c, u}` object; values are `WireValue`s (null, bool, 64-bit integer, double, string, array).
- **Highlights:** `highlight_offset` / `highlight_length` are UTF-16 code units (Swift `String.utf16` offsets). Capture length limits (500 and 5,000 characters) count Unicode code points instead.
- **Text order.** Every order or prefix range that must match Android is done in SQL with the default `BINARY` collation, which on UTF-8 is Unicode scalar order. That covers user `match_key` and `name_key` and dictionary `key` and `form_key` (Words A–Z, autocomplete, tag lists). Swift `String` comparison uses Unicode canonical ordering, so it is never used for these lists. Where an in-memory comparison cannot be avoided (the App Group vocabulary index lookup, the fixture tests), it compares UTF-8 bytes. `COLLATE NOCASE` and `LOCALIZED` are never used. Pinned by `fixtures/normalization/text-order.json`.

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

**Author rank `u`:** 1 for any change caused directly by a user action (typing, picking a suggestion, editing, exclude/resume, tagging/untagging, reordering Senses, deleting). 0 for everything automatic (enrichment fills, `enrichment_status`, setting and clearing `needs_check`, Card creation, `merged_into`, Device bookkeeping, defaults). "The user has edited this field" is simply `u = 1` in `field_clocks`; there is no separate flag. Write rules (`Tx.set`):
- One HLC stamp per write call.
- A no-op write (same value, rank not rising) creates no new clock and no outbox row.
- An automatic (rank 0) write never replaces a field whose current rank is 1.

## 2. One logical schema, per-platform transport tables

- **Shared with Android:** every synced table and its columns, and the shared local tables `pending_changes`, `sync_state` (the shared keys) and `schema_meta`. Table names, column names, types, enum spellings and the meaning of every column are identical on both platforms. Local derived columns (`match_key`, `*_fold`, `canonical_*`, card cache, `review_day`) are also identical, because the shared fixtures exercise them.
- **Per platform:** sync-transport and extension bookkeeping.
  - iOS has `cloud_record_meta` (CloudKit system fields) and `inbox_import` (Share Extension inbox).
  - Android has `drive_file` and `drive_file_owner`. iOS does **not** create these two tables.
- **`schema_meta.version` is per platform.** No database file ever moves between iOS and Android. The cross-platform contracts are the per-record `schema` in the wire envelope and the backup file's `version` and `protocol` ([Export and restore](#9-export-and-restore)).

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
| `origin` | TEXT | iOS writes `typed` (Add screen) and `shared` (Share Extension). `text_selection` is written by Android; `imported` is later. |
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
| `translation_src`, `definition_src`, `pos_src` | TEXT NULL | `user` / `wiktionary` / `mt_apple` (Apple Translation) / `mt_mlkit` (written by Android; kept as is) |
| `dict_version` | TEXT NULL | e.g. `2026.11.1` |
| `dict_headword_key` | TEXT NULL | |
| `dict_sense_ordinal` | INTEGER NULL | |
| `translation_fold`, `definition_fold` | TEXT NULL | *local*, search folds |
| `canonical_id`, `canonical_entry_id` | BLOB | *local* |

**Provenance of picked suggestions** (also in the Edit form): a Sense created from a dictionary or machine-translation suggestion stores the suggestion's `_src`, `dict_version`, `dict_headword_key` and `dict_sense_ordinal`, as long as the user did not change its translation, definition or part of speech before saving. If any of the three was edited, the Sense is saved as a user Sense: `_src = user` for the fields, no dictionary reference. On iOS `EntryDraft` keeps the original suggestion beside the draft row and compares at save time (test `entryDraftSuggestedMeaningKeepsProvenanceUntilEdited`).

### 3.4 `source`

| Column | Type | Notes |
|---|---|---|
| `id` | BLOB PK | `v5("source:<urlKey>")` when a URL exists, else UUIDv7 |
| `kind` | TEXT | `web` / `app` / `other` / `suggested` (an Entry added from a related-word suggestion; `title` = the headword it was suggested from) |
| `url` | TEXT NULL | |
| `title` | TEXT NULL | |
| `app` | TEXT NULL | iOS writes "Safari" when the share came with Safari's page data, else NULL ([capture-and-enrichment.md](capture-and-enrichment.md)). Android writes the label of the calling app. |
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

The cache is rebuilt by replaying the Card's logs ([scheduler.md](scheduler.md)). A merged-away Card (its `canonical_card_id` is another Card) has all cache columns NULL. Cards are created with rank 0, for `recognition` and `recall`, when an Entry is canonical, live and `active` and has at least one live Sense with a non-empty translation. `cloze` Cards are created only for Entries with a Context that has a sentence and a highlight. Entries without a translation never appear in Review, the widget or Home due counts.

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
| `review_type` | TEXT NULL | *local*; reserved, never written by any code path |
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

A change to `fsrs_w`, `desired_retention` or `scheduler_version` (local or pulled) triggers a full Card rebuild. An `fsrs_w` that does not hold exactly 21 numbers is ignored and the defaults are used.

### 3.10 `device`

| Column | Type | Notes |
|---|---|---|
| `id` | BLOB PK | UUIDv7, new per installation and per restore |
| `platform` | TEXT | `ios` (Android writes `android`) |
| `display_name` | TEXT | `UIDevice.current.model` (for example "iPhone"). Never the user-set device name, which may contain a person's name and would sync. |
| `first_seen` | INTEGER | |
| `is_this_device` | INTEGER NOT NULL DEFAULT 0 | *local* |

## 4. Local-only tables

### 4.1 Shared with Android

| Table | Columns | Purpose |
|---|---|---|
| `pending_changes` | `record_id` BLOB NOT NULL, `type` TEXT NOT NULL, `field` TEXT NOT NULL, `clock` TEXT NOT NULL; PK `(record_id, field)` | The outbox. Upserted in the same transaction as every local write, **only while the outbox is active**. `field = '*'` means the whole record; envelope changes use `_deleted` and `_mergedInto`; `_cloudDelete` (clock `''`) is a purged child still to be deleted from iCloud. `type` = the wire type, which is the table name. Rules: [sync.md](sync.md#outbox). |
| `sync_state` | `key` TEXT PK, `value` TEXT | Key/value bookkeeping, keys below. |
| `schema_meta` | `version` INTEGER NOT NULL | iOS's local schema version ([Migrations](#7-migrations)). |

`sync_state` keys on iOS:

| Key | Value | Shared with Android |
|---|---|---|
| `hlc` | `{ms, counter}` of the hybrid logical clock, written in the same transaction as each write | yes |
| `lastServerTime` | newest CloudKit modification date seen (Unix ms) | yes (meaning) |
| `lastSyncAt` | end of the last successful cycle (Unix ms) | yes |
| `excludedRecords` | `{appVersion, ids}`: records not uploaded (too large or rejected); cleared when the app version changes | yes |
| `cloudUser` | iCloud user record name the local data syncs with; no email is stored. The outbox is active when it is set and `cloudDeleted` is not. | iOS |
| `changeToken` | base64 of the archived CloudKit zone change token | iOS |
| `zoneCreated` | `1` once the zone was created for `cloudUser` | iOS |
| `zoneGeneration` | adopted `zone-info` generation | iOS |
| `cloudDeleted` | `1` after the iCloud data was deleted (outbox inactive until "Back up this device again") | iOS |

### 4.2 iOS transport and extension tables

`cloud_record_meta`: `record_id` BLOB PK, `system_fields` BLOB NOT NULL. The archived CloudKit system fields (record ID and change tag) of each record known to be in iCloud, so a save carries the change tag ([sync.md](sync.md#system-fields)). Filled on fetch and on save; a row goes when the record is deleted from or by iCloud. Cleared, together with `changeToken`, on an account switch, Back up this device again, iCloud data deleted, device restore and Remove all data.

`inbox_import`: `inbox_id` BLOB PK, `imported_at` INTEGER NOT NULL. One row per imported Share Extension inbox file, written in the same transaction as the capture, so a file that was imported but not yet deleted is never imported twice ([capture-and-enrichment.md](capture-and-enrichment.md)).

GRDB also keeps its own `grdb_migrations` table with the names of the applied migrations.

## 5. Derived text keys and folds

Computed in `ToriCore`, stored in *local* columns in the same transaction as their source field (local write, applying a pulled record, restore), and never synced. The exact character lists and corner cases are normative in `fixtures/README.md` ("Rules for the text functions") and the `fixtures/normalization/` cases. Summary:

- **Match key** (`entry.match_key`; also the *translation key* used to compare translations):
  1. Unicode NFC.
  2. Map apostrophe, quote and dash variants to `'`, `"` and `-`; map space separators to U+0020.
  3. Remove the listed default-ignorables.
  4. Lowercase per code point with the locale-free, context-free default mapping (Σ → σ always).
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
- **Source key without URL:** match key of `title` + the app name as stored + whether `kind` is `suggested`.

Swift specifics:
- NFC: `precomposedStringWithCanonicalMapping`.
- Iterate by Unicode scalar, never by `Character` (grapheme cluster).
- Lowercase: `Unicode.Scalar.Properties.lowercaseMapping` per scalar. Never `String.lowercased()`, which applies context rules.
- Punctuation: `Unicode.Scalar.Properties.generalCategory` in the seven P* categories.
- The quote, dash, space, whitespace and ignorable maps are explicit scalar lists in `TextKeys.swift`, not property lookups.
- Punycode is a hand-written encoder in `URLKey.swift`.

**Canonical IDs:** `canonical_id` = the end of the record's `merged_into` chain (itself if none). Children carry `canonical_entry_id` (and `canonical_card_id` / `canonical_tag_id`), recomputed when a parent arrives or merges ([sync.md](sync.md)).

## 6. Integrity rules

### 6.1 Indexes

As on Android:
- `entry (language_pair_id, match_key)`, `entry (canonical_id)`, `entry (created_at)`, `entry (status)`;
- `sense (canonical_entry_id)`, `sense (entry_id)`;
- `context (canonical_entry_id)`, `context (entry_id)`;
- `card (due_day)`, `card (canonical_card_id)`, `card (canonical_entry_id)`, `card (entry_id)`;
- `review_log (canonical_card_id, reviewed_at, id)`, `review_log (review_day)`, `review_log (card_id)`, `review_log (owner_entry_id)`;
- `tag (name_key)`;
- `entry_tag (canonical_entry_id)`, `entry_tag (entry_id)`, `entry_tag (tag_id)`.

`card (due_day)` is a plain index over every Card, including merged-away Cards (cache NULL); there is no partial index on canonical Cards. `cloud_record_meta` and `inbox_import` need no index beyond their primary keys.

### 6.2 Unique keys are not constraints

"At most one live Entry per match key" (and one Source per URL key, one Tag per tag key) cannot be a `UNIQUE` index, because sync legitimately delivers duplicates from other devices. None of these indexes is `UNIQUE`. The deterministic duplicate merge ([sync.md](sync.md#duplicate-merge)) runs at the end of every write transaction that touched a natural key: after each pulled page and after local edits.

### 6.3 Foreign keys and orphans

- **No FK constraints at all.** Synced references (`entry_id`, `card_id`, `sense_id`, `source_id`, `tag_id`, `language_pair_id`, `merged_into`, `owner_entry_id`) are plain indexed columns. (`foreign_keys` is on, but no table declares one.)
- Reason: CloudKit returns changes in its own order, not parent first, and each fetched page is its own transaction. A child may be committed before its parent.
- **Orphan rule:** a row whose parent (Entry, Card, Tag, Source, merge survivor) is not present locally is stored as is. It is **hidden** from the UI, the queue and stats, and **excluded from replay**. Every read reaches children through joins on the live canonical parent, so orphans drop out without flags.
- **When the parent arrives**, in the same transaction that applies it: recompute the children's derived columns (`canonical_*`, `review_day`), then replay the affected Cards. The result equals receiving everything at once.

### 6.4 Deletion

Deletion is logical first. A tombstone on the Entry hides its children through the same joins. Children are then purged with one `DELETE` per child table by `entry_id` / `canonical_entry_id` / `owner_entry_id` (never `ON DELETE CASCADE`):
- while the outbox is inactive: immediately;
- while the outbox is active: when the Entry tombstone has been saved to iCloud (or arrives by pull), followed by the cloud purge ([sync.md](sync.md#cloud-purge)).

The purge covers the whole merge group. A deletion with Undo is held in memory during the Undo toast. The tombstone is written when the toast closes, at the next deletion, or when the app goes to the background ([architecture.md](architecture.md)).

## 7. Migrations

- GRDB `DatabaseMigrator` with named, forward-only migrations (`Schema.swift`), run in `ToriStore.init` before any read or write. GRDB records applied migrations in `grdb_migrations`, so reopening runs nothing twice.
- **`v1`** creates every table and index in this file except `cloud_record_meta`, and inserts `schema_meta.version = 1`.
- **`v2-cloud`** creates `cloud_record_meta` and deletes the `sync_state` keys of the retired own-backend sync (`cursor`, `accountId`, `lastSyncedAccountId`, `pendingAccountChoice`, `adoptedAccountId`, `lastProvider`, `signInBaseline`).
- **`schema_meta.version` is still 1:** `v2-cloud` does not bump it, and nothing reads it. The migration name list is the real version record.
- The app opens the store off the main actor at launch, before the dictionary, inbox import and sync ([architecture.md](architecture.md)). The Share Extension and widget never open `user.sqlite`, so no reader can see a half-migrated schema.
- **Additive changes are the norm** (new nullable column, new table). Renames and drops: add the new column, copy, stop reading the old one, drop it in a later release.
- **Synced shape changes are coordinated with Android.** A new synced column or record type is introduced on both platforms, with the same name, type and per-record `schema` bump. Fields this version does not know live in `extra`; unknown record types are skipped on pull ([sync.md](sync.md#schema-evolution)). No migration ever requires a full re-upload.
- **Derived columns follow their rule.** A change to a shared text rule that feeds a stored column (match key, tag key, URL key, search fold) is a migration. It recomputes every affected column (`match_key`, `name_key`, `url_key`, `*_fold`) and then runs the duplicate merge. Otherwise iOS and Android results drift for existing rows.
- **Tests:** `migrationsAndPragmas` checks the fresh schema, the pragmas and that reopening is safe.

  > Not yet implemented: fixture databases of historical iOS schema versions and a test that migrates each to the current schema with identical logical content ([testing.md](testing.md)).

## 8. Settings storage

### 8.1 Synced versus per-device

| Synced (`settings` record) | Per device (UserDefaults, never synced) |
|---|---|
| New words per day; desired retention; FSRS parameter set (`fsrs_w`, `params_id`); scheduler version. | Everything in the per-device UserDefaults below. |

The review-day start (04:00) is a constant, not a setting. The app language is the per-app language in iOS Settings, not stored by ToriWords ([architecture.md](architecture.md)).

### 8.2 Per-device settings in UserDefaults

`UserDefaults.standard` of the app. Included in OS backup.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `reminderEnabled` | Bool | false | Daily reminder on/off |
| `reminderHour` | Int | 19 | Reminder time, hour |
| `reminderMinute` | Int | 0 | Reminder time, minute |
| `accent` | String | `us` | Pronunciation accent: `us` / `uk` |
| `autoPlayOnReveal` | Bool | false | Speak the word when the card is revealed |
| `swipeDemoShown` | Bool | false | The Review swipe demo was shown |
| `reminderOfferShown` | Bool | false | The one-time reminder offer after the first finished session was shown |
| `widgetHintSnoozedUntil` | Double | 0 | Epoch seconds; the Add screen's widget hint stays hidden until then ("Not now" sets now + 24 h) |
| `dictionaryVersion` | String | — | Last seen dictionary version; a change re-runs enrichment on `unavailable` Entries |

The reminder time is two keys (hour and minute), not one minutes value as on Android. There is no dictionary checksum key: the dictionary is read from the app bundle. The Share Extension's one-time tip flag lives in the sticky file below.

### 8.3 Sticky capture fields

File `capture-sticky.json` in the App Group container (`group.com.toriwords.app`), written atomically (temporary file, then rename). Not excluded from backup.

```json
{ "format": 1, "updatedAt": 1764238500000, "sourceTitle": "The Guardian", "tags": ["news"], "tipShown": true }
```

| Key | Type | Meaning |
|---|---|---|
| `format` | Int | File format, 1 |
| `updatedAt` | Int (Unix ms) | Last Save in the Share Extension |
| `sourceTitle` | String (absent = none) | Last used source title |
| `tags` | [String] | Tag names, in the order shown |
| `tipShown` | Bool | The Share Extension's one-time tip was shown; never expires |

The source title and tags are offered again for **30 minutes** after `updatedAt`. Written and read **only by the Share Extension**; the Add screen does not pre-fill from them ([capture-and-enrichment.md](capture-and-enrichment.md)).

## 9. Export and restore

### 9.1 Formats

**JSON backup** (restorable). File name `ToriWords-backup-YYYY-MM-DD.json`, dated in the device's time zone:

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

- `records` holds every **non-deleted** synced record as a full sync envelope, with field clocks and ranks (envelope format: [sync.md](sync.md#envelope-wire-format)), in `RecordType` order (parents first) and by ID within a type. Merged-away records are included; tombstones and the hidden children of deleted Entries are not.
- `version` is the backup file format version; `protocol` is the record envelope protocol.
- `attribution` is the dictionary's licence text (`meta.licence_text` of the bundled dictionary, else the built-in default text in `ExportFile.swift`).
- The file is the same on iOS and Android. A file from either platform restores on the other; this is the only way to move words between them.

**CSV** (lossy, not a backup). File name `ToriWords-YYYY-MM-DD.csv`. UTF-8, RFC 4180, CRLF line ends. Fields containing `,`, `"`, CR or LF are quoted, with `"` doubled.
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

Settings → Data → Export, offline, no iCloud needed. The screen offers "Backup (JSON)" and "Spreadsheet (CSV)". The Export button is disabled with a note ("Add words to export them.") when there are no live words.
- The file is built off the main actor in one call, held in memory, and written to the temporary directory under its file name. The screen shows indeterminate progress with Cancel; there is no per-word progress.
- The file is then offered in the system share sheet (`UIActivityViewController`): Save to Files, AirDrop, Mail and so on. There is no separate "Save to device" picker; Save to Files covers it. No permission is needed.
- On failure: "Something went wrong".

> Partly implemented: export is not streamed. A very large vocabulary is held in memory twice (records and encoded file) while exporting.

### 9.3 Restore

Settings → Data → Restore from backup. The system file picker (`fileImporter`) for `.json` files; no permission is needed.

1. **Pre-sync:** run one sync cycle first, so Entries deleted on other devices are local tombstones. If that cycle fails, or iCloud is off, restore runs against local tombstones only. An Entry deleted elsewhere but not yet fetched is then counted as imported and disappears at the next sync (delete wins).
2. **Validate the header:** if `format` ≠ `toriwords-backup`, or `version`/`protocol` are missing, or the file does not decode → "This is not a ToriWords backup", nothing changes. If `version` or `protocol` is higher than the app supports (both 1 in v1) → "Update the app", nothing changes.
3. **Apply:** decode the whole file, then apply the records **as if pulled** ([sync.md](sync.md#applying-pulled-records-one-transaction-per-page)), in pages of 1,000 records, one transaction each. Unknown fields are kept in `extra`; unknown types are skipped. While the outbox is active, each inserted or updated record gets a `*` outbox row. Records whose Entry is tombstoned locally are not restored.
4. **Then:** each page's transaction already runs the duplicate merge, Card creation and replay. Finally, one more sync cycle.
5. **Summary counts:**
   - imported = Entry IDs new to this device that are their own canonical Entry;
   - merged = Entry IDs new to this device that merged into an existing Entry;
   - deleted earlier = Entry IDs tombstoned locally and therefore not restored.

Restoring the same file twice changes nothing (test `exportRestoreRoundTripIsIdempotent`).

> Partly implemented: restore reads and decodes the whole file in memory rather than as a stream.

## 10. OS backup

iOS backs up the app container (iCloud Backup and Finder/encrypted backups, and Quick Start device transfer):

| Item | Location | Backed up |
|---|---|---|
| `user.sqlite`, `-wal`, `-shm` | Application Support | yes |
| `device-marker` | Application Support | **no** (`isExcludedFromBackup`) |
| UserDefaults | app preferences | yes |
| `capture-sticky.json`, `widget-snapshot.json`, `vocab-index.json`, `inbox/` | App Group container | yes (no exclusion is set) |
| Export files | temporary directory | no |

- `user.sqlite` is backed up as is. The WAL is checkpointed (`TRUNCATE`) on every move to the background, so a backup holds a consistent, mostly checkpointed database.
- **Device marker:** a 16-byte file holding this installation's Device ID. At launch (`ToriStore.launch`), if the `device` row with `is_this_device = 1` does not match the marker:
  - no such row: fresh install. A new Device row, the LanguagePair and Settings defaults.
  - a row exists but the marker is missing or different: **restored from a backup**. A new Device ID (the old row stays with `is_this_device = 0`), the change token and the stored system fields are cleared, and every record is marked pending ([sync.md](sync.md#device-restore)). `cloudUser` and `cloudDeleted` stay.
  - Then the marker is rewritten.
- There is no 25 MB quota as on Android; the backup counts against the user's iCloud storage.

## 11. Remove all data from this device

Settings → Data → Remove all data from this device. The app first warns:
- without active sync: all words, review history and tags are deleted from this device, and this can't be undone;
- with active sync: the words stay in iCloud and come back at the next sync, unless iCloud data is deleted in Settings → iCloud sync; if there are unsynced changes, how many will be lost.

Wording: [copy.md](copy.md).

Through the sync engine (a running cycle is superseded), in one transaction (`Account.deleteUserRecords`):
- delete all rows of every synced table **except `device`** (all Device rows are kept, including this device's);
- recreate the LanguagePair and Settings defaults (rank 0);
- delete all of `pending_changes`;
- delete all `cloud_record_meta` rows and `changeToken`.

Then `lastSyncAt` is cleared, so the status is "Not synced yet".

Kept: `cloudUser`, `cloudDeleted`, `zoneCreated`, `zoneGeneration`, `excludedRecords`, `hlc`, `lastServerTime`, `inbox_import`, UserDefaults and the sticky file. If sync is on, the next cycle downloads everything iCloud still has. Afterwards the app rewrites the widget snapshot and vocabulary index and re-arms the reminder.

## 12. Expected size

10,000 Entries, 30,000 Senses and Contexts, 20,000 Cards and 300,000 ReviewLogs take roughly 30–60 MB with indexes (to be measured). Well within device limits; it counts against iCloud storage both in the device backup and in the sync zone.

## Open questions

- `schema_meta.version` stayed 1 after `v2-cloud`. Bump it in the next migration, or drop the table on iOS, since GRDB's migration list already records the version?
- `capture-sticky.json` and the other App Group files are included in device backups, while Android excludes its sticky fields. Exclude the sticky file (and the regenerable widget snapshot and vocabulary index) from backup?
- `review_log.review_type` exists on both platforms but nothing writes it. Keep it reserved or drop it in a later migration?
- Export and restore hold the whole file in memory. At the planning scale (300k ReviewLogs) that may be well over 100 MB. Stream both before release?
