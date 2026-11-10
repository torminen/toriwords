# Local storage

Status: **Proposed**. Pending owner confirmation in step 5. Nothing here is a `decision` yet.

Each device holds the user's full vocabulary and review history and works offline ([local-first](memory://8)). This document covers the storage engine on each platform, the logical schema, migrations, sharing with extensions and widgets, and OS backup for users without an account.

Inputs: [domain-model.md](../product/domain-model.md). Related: [scheduler.md](scheduler.md), [sync.md](sync.md), [capture-and-extensions.md](capture-and-extensions.md), [dictionary-data.md](dictionary-data.md).

## 1. Principles

1. **SQLite on both platforms, with the same logical schema.** Table and column names, types, and constraints are specified once (§4) and declared natively by each app in its own migrations. No shared code ([native apps](memory://7)); the shared thing is the spec plus fixtures.
2. **Two databases per device:**
   - `user.sqlite`: the user's data. Read-write. Backed up. Synced.
   - `dictionary.sqlite`: Wiktionary-derived lookup data. Read-only, replaceable, never backed up, never synced ([dictionary-data.md](dictionary-data.md)).
   - User data **never references dictionary row ids**. Provenance is stored as `(dictionaryVersion, headwordKey, senseOrdinal)` plus a copy of the text, so a new dictionary build can't break user data.
3. **One writer process.** Only the main app process opens `user.sqlite`. Extensions and widgets exchange data with it through small files (§6). This avoids most cross-process SQLite pitfalls on iOS.
4. **The ReviewLog table is append-only.** Card scheduling columns are a cache that can be rebuilt by replay ([scheduler.md](scheduler.md) §7).

## 2. iOS engine

| Option | For | Against |
|---|---|---|
| **SwiftData** | Newest Apple persistence API (goal G1 in [memory://10](memory://10)); SwiftUI `@Query` integration. | Schema is generated from model classes, so we don't control column names or types, the identical-schema principle is hard to keep, and the sync engine needs low-level control (change tracking, tombstones, bulk upserts in one transaction). No FTS. Cross-process guarantees between app and extensions are not documented (open Apple forum threads, 2025–2026); WWDC26 guidance is "the app owns the store and migrations". Migration history has rough edges. |
| **Core Data** | Mature, cross-process tested, Apple-supported. | Legacy direction; same object-graph mismatch with a record-level sync protocol; no FTS; verbose. |
| **GRDB.swift** (SQLite toolkit) | Full SQL control, so the same schema as Android; WAL `DatabasePool` with concurrent reads; FTS5; `ValueObservation` for reactive SwiftUI updates; explicit, testable migrations; documented app-group sharing guidance; MIT, actively maintained. | Third-party dependency; less "Apple-native" than SwiftData. |
| Raw SQLite C API | No dependency. | We'd re-write GRDB. |

**Recommendation: GRDB** for both databases. Usefulness wins over newest-API (tie-breaker in [memory://10](memory://10)): sync correctness and parity need SQL-level control, and the dictionary needs FTS anyway. SwiftUI stays modern on top (`@Observable` view models fed by `ValueObservation`).

## 3. Android engine

| Option | For | Against |
|---|---|---|
| **Room** (Jetpack) | Google's recommended persistence; Kotlin coroutines/Flow; compile-time checked SQL; `@Fts4`/raw FTS; auto and manual migrations with schema export JSON (good for review and testing); bundled-SQLite driver option (`androidx.sqlite:sqlite-bundled`), so the SQLite version and FTS5 are the same on every device. | Annotation-based entities hide some SQL; relations are clumsy (we use plain queries instead). |
| **SQLDelight** | SQL-first: the `.sq` files read almost like §4; generates type-safe Kotlin; good migrations story. | Not Jetpack; smaller ecosystem; the Android-recommended path is Room. |

**Recommendation: Room** with the **bundled SQLite driver**, written SQL-first (entities mirror §4 exactly; complex reads via `@Query` with explicit SQL). The bundled driver gives FTS5 and the same SQLite behaviour as iOS. SQLDelight is a close second; pick it instead if the team prefers SQL files as the source of truth.

## 4. Logical schema of `user.sqlite`

Draft, based on the domain model. Column names are normative once confirmed. Sync metadata follows [sync.md](sync.md) (per-field LWW with HLC).

Conventions:
- `id`: UUIDv7, stored as 16-byte `BLOB`.
- Instants: `INTEGER` Unix milliseconds UTC. Offsets: `INTEGER` minutes.
- Enums: `TEXT` with the exact spellings below.
- Every synced table has the sync columns ([sync.md](sync.md) §2.1, §3):
  - `field_clocks TEXT NOT NULL`: JSON map of field name → `{c, u}` (HLC string, author rank).
  - `deleted INTEGER NOT NULL DEFAULT 0`: terminal tombstone.
  - `merged_into BLOB NULL`: terminal redirect to a surviving duplicate.
  - `extra TEXT NULL`: JSON with fields this app version does not know, kept with their clocks and sent back unchanged.
- Local-only, non-synced columns: `canonical_id BLOB` on `entry`, `sense`, `context`, `tag` (resolved `merged_into` chain, indexed), and on child tables `canonical_entry_id`. They are recomputed after every pull ([sync.md](sync.md) §7.3).
- Local-only tables: `pending_changes(record_id, type, field)` (the outbox, appended in the same transaction as each write), `sync_state(key, value)` (cursor, HLC state `{ms, counter}`, account ID).

| Table | Columns (besides sync columns) | Notes |
|---|---|---|
| `language_pair` | `id`, `native_lang` (BCP-47, `ru`), `target_lang` (`en`), `created_at` | One row in v1. |
| `entry` | `id`, `language_pair_id`, `text`, `match_key`, `ipa`, `note`, `status` (`active`/`excluded`), `excluded_reason` (`known`/`paused`/NULL), `enrichment_status` (`pending`/`done`/`unavailable`), `origin` (`typed`/`shared`/`text_selection`/`imported`), `created_at`, `updated_at` | `kind` is derived from `text`, not stored. Index on `(language_pair_id, match_key)` — **not UNIQUE** (§8). |
| `sense` | `id`, `entry_id`, `translation`, `definition`, `part_of_speech`, `position` (REAL, fractional index), `translation_src`, `definition_src`, `pos_src` (`user`/`wiktionary`/`mt_apple`/`mt_mlkit`), `dict_version`, `dict_headword_key`, `dict_sense_ordinal` | `position` as fractional index so concurrent reorders merge per field; ties broken by id. "User has edited this field" is the field's author rank `u = 1` in `field_clocks`; there is no separate mask. |
| `source` | `id` (UUIDv5 of `url_key` when a URL exists, else UUIDv7), `kind` (`web`/`app`/`other`), `url`, `url_key` (normalised URL), `title`, `app` | Deterministic id makes same-URL Sources collapse ([sync.md](sync.md) §4). |
| `context` | `id`, `entry_id`, `sense_id` NULL, `sentence`, `highlight_offset`, `highlight_length` (UTF-16 code units, as in the domain model; §8.4), `source_id` NULL, `captured_at` | |
| `card` | `id` (deterministic UUIDv5 of entry + direction, [sync.md](sync.md) §4), `entry_id`, `direction`, `import_ref`, cache: `stability` REAL, `difficulty` REAL, `last_review_day` INTEGER, `due_day` INTEGER, `reps`, `lapses`, `stage`, `params_id` | Cache columns are **not synced**; recomputed locally ([scheduler.md](scheduler.md) §7). Index on `(due_day)` where active. |
| `review_log` | `id`, `card_id`, `reviewed_at`, `utc_offset_min`, `rating` (1–4 FSRS), `answer_ms`, `device_id`, `original_rating` NULL, `import_ref` NULL; local-only derived: `review_day`, `review_type`, `canonical_card_id` | Append-only: synced columns are never updated. Removed only by Entry deletion. |
| `tag`, `entry_tag` | `tag`: `id`, `name`, `name_key`; `entry_tag`: `id` (deterministic UUIDv5 of entry + tag), `entry_id`, `tag_id`, `present` | Pending PD-3. Add/remove flips `present` (LWW), so re-tagging after un-tagging works; no tombstones on links ([sync.md](sync.md) §4). |
| `settings` | one row, id = UUIDv5 `settings`; one column per synced setting, sync columns | Synced settings are the fields of one record, merged per field ([sync.md](sync.md) §4). Which settings sync: PD-16. Non-synced settings go to platform settings (UserDefaults / DataStore). |
| `device` | `id`, `platform`, `display_name`, `first_seen` | This device's row is created on first run. |
| `inbox_import` | `inbox_id`, `imported_at` | Local only. Makes share-extension import idempotent ([capture-and-extensions.md](capture-and-extensions.md)). |
| `schema_meta` | `version` | Local only. |

**Foreign keys:** declared with `ON DELETE CASCADE` for local physical cleanup, but **deletion is logical first** (tombstone on the Entry; children are hidden by joins and purged after the tombstone has synced). Sync may deliver children before parents, so FK enforcement during a sync batch is deferred (`PRAGMA defer_foreign_keys = ON` inside the transaction).

**Expected size:** 10 000 entries, 30 000 senses/contexts, 20 000 cards, 300 000 review logs ≈ 30–60 MB with indexes (`nv`, to measure). Well within device limits. Above the 25 MB Android cloud-backup quota at the high end (§7).

## 5. Migrations

- Each app keeps an ordered list of numbered, forward-only migrations (`GRDB DatabaseMigrator` / Room `Migration` objects). `schema_meta.version` is identical across platforms for the same logical schema; a migration that changes the logical schema bumps it on both.
- Migrations run at app start, **only in the main app process**, before any UI or sync.
- Additive changes (new nullable column, new table) are the norm. Renames and drops go through "add new, copy, stop reading old, drop in a later release".
- Records carry a per-type schema version. An older app stores fields it does not know in `extra` and sends them back unchanged, so it never erases data written by a newer app. Unknown record types are skipped and later backfilled download-only ([sync.md](sync.md) §10). No change ever requires a full re-upload (I7).
- Migration tests: each platform has a fixture DB per historical version and checks it migrates to the current one with identical logical content (same fixture inputs on both platforms, [parity-testing.md](parity-testing.md)).

## 6. Sharing with extensions and widgets

| Consumer | iOS | Android |
|---|---|---|
| Share / text-selection capture | Share Extension runs in a **separate process** with a ~120 MB memory limit (observed, not documented by Apple). It **does not open `user.sqlite`**. It writes one JSON file per capture into `AppGroup/inbox/` (atomic write, file name = capture UUIDv7). The app imports and deletes these on launch/foreground. | `ACTION_PROCESS_TEXT` / `ACTION_SEND` activity runs **in the app process** and writes through the normal repository. No inbox needed. |
| Dictionary lookup in capture UI | The extension opens `dictionary.sqlite` **read-only, immutable** (`?immutable=1`), from the App Group. No locks, no WAL, safe under suspension. | Same process; same read-only connection. |
| Due-count widget | Widget extension reads `AppGroup/widget-snapshot.json`, written by the app after every change. It does not open the DB. | Glance widget runs in the app process; it reads the same snapshot (from app-private storage) for symmetry and cheap rendering. |

**Why files, not a shared SQLite DB on iOS:**
- A process suspended while holding a SQLite lock in an App Group container is killed by iOS (`0xDEAD10CC`); avoiding this needs careful lock discipline in both processes (GRDB documents the workarounds, but they are easy to get wrong).
- Change observation does not cross processes (GRDB and SwiftData alike), so the app would need Darwin notifications anyway.
- Schema migrations must be owned by one process; an extension started right after an app update could open a not-yet-migrated DB.
- A capture is a tiny, append-only, idempotent message. A file per capture is the simplest correct transport.

Where `user.sqlite` lives:
- iOS: in the App Group container **only if** a future extension really needs it; otherwise in the app's own Application Support. Recommendation: app container (Application Support) in v1. `dictionary.sqlite` goes to the App Group container so the extension can read it.
- Android: app-private `databases/`.

WAL mode on both platforms, `synchronous = NORMAL`, `foreign_keys = ON`, periodic `wal_checkpoint(TRUNCATE)` when the app goes to background (keeps backups consistent and small).

## 7. Backup for users without an account

Users who never sign in have no cloud copy from Toriwords (see the account & sync feature in the product spec). OS backup is their safety net:

| | iOS | Android |
|---|---|---|
| Mechanism | iCloud / Finder device backup includes the app container and App Group container. | Auto Backup to Google Drive (quota **25 MB per app**) and device-to-device transfer (no quota). |
| Include | `user.sqlite` (checkpointed), preferences. | `user.sqlite` via `data_extraction_rules.xml` (`cloud-backup` and `device-transfer`). |
| Exclude | `dictionary.sqlite` (`isExcludedFromBackup`), inbox, snapshot, caches. | `dictionary.sqlite`, caches. |
| Caveat | None in practice. | **A large collection exceeds 25 MB and Auto Backup silently stops.** Mitigation: (a) accept, and tell the user in settings that sign-in is the reliable backup; (b) back up a compressed export instead of the raw DB (Auto Backup can include any file; a zstd JSON export of 300k logs is likely ≤ 10 MB, `nv`). Recommendation: (b) as P1, written by a periodic worker. |

After restore on a new device, the app keeps the user's data but generates a **new Device id** (the restored `device` row is marked foreign), so two devices never share an id if the old one is still in use.

A user-visible manual export/import file (JSON/CSV, A5) is a product decision; if adopted, it reuses the same export format.

## 8. Domain-model issues relevant to storage (to raise with product_writer and sync)

1. **Unique match key can't be a DB constraint.** "At most one non-deleted Entry per match key" can't be enforced by a UNIQUE index, because sync legitimately delivers a second Entry with the same key from another device. The storage keeps a plain index and the **merge procedure** runs after each sync batch and on local edits. Same applies to Source by URL and Tag by name.
2. **(Resolved in [sync.md](sync.md) §4, §7: deterministic Card IDs + smallest-ID survivor + local canonical-ID columns; ReviewLogs are never rewritten.)** **Merging conflicts with "ReviewLog is never edited".** The domain says the loser's ReviewLogs "belong to the surviving Entry's Card". Re-pointing `review_log.card_id` is an edit. Options for [sync.md](sync.md): (a) keep logs immutable and add a `card.merged_into` redirect, with replay collecting logs of the Card and all Cards redirected to it; (b) allow exactly one mutation, the card reference, by the merge procedure; (c) make Card ids deterministic, e.g. UUIDv5(entry id, direction), and the merge choose the surviving Entry deterministically (e.g. lowest id) so both devices converge. Recommendation: (a) + deterministic survivor = lowest Entry id. Needs agreement with sync.md.
3. **`elapsed since previous review` should not be stored as truth.** After two devices' concurrent logs merge, the stored value from one device is wrong relative to the merged order. Recommendation: derive it during replay from review days; keep it out of the stored schema, or store it as informational only.
4. **Highlight offsets need a unit.** Swift `String` and Kotlin `String` index differently (grapheme clusters vs UTF-16). **Resolved:** the domain model fixes offset + length in UTF-16 code units (Kotlin native; Swift via `String.utf16` / `NSRange`).
5. **Sense `order` under concurrent edits.** Integer positions collide when two devices reorder or add Senses offline. Recommendation: fractional index (`REAL` or string key) with id tie-break.
6. **`updated at` on Entry vs sync clock.** The user-visible `updated at` and the sync clock should be separate fields; the domain model already treats sync versioning as a placeholder, which is fine.
7. **Entry `kind` is derived.** Not stored, to avoid drift with `text` (same in the domain model; just confirming).
8. **Preferences need per-key identity** for sync (the `preference` table keyed by name), pending PD-16.

## 9. Open questions

- **Q-L1 (owner):** GRDB on iOS instead of SwiftData (newest-API trade-off). Recommendation: GRDB.
- **Q-L2 (owner):** Room vs SQLDelight. Recommendation: Room + bundled SQLite.
- **Q-L3 (product):** is a user-visible export file in v1 (A5)? It would also serve as the Android backup payload.
