# Toriwords Android

Modules: `core` (pure Kotlin port of ToriCore: IDs, text keys, HLC, merge, FSRS), `store` (Room port of ToriStore),
`sync` (Drive sync engine), `app` (Compose UI).

## Build & test

```sh
. /home/unc/.cache/toolchain/env.sh   # JDK, Android SDK, Gradle caches (agent environment)
cd android
./gradlew :core:test :store:test      # JVM unit tests (store runs on Robolectric with an in-memory DB)
./gradlew assembleDebug
```

## SQLite driver

`store` uses Room 2.8 on `BundledSQLiteDriver` (`androidx.sqlite:sqlite-bundled`), not the framework SQLite:

- one SQLite version (3.50, FTS5 enabled) on every API level, matching the behaviour iOS relies on (unsigned BLOB order,
  BINARY collation, FTS5 for the dictionary later);
- the same driver runs in JVM unit tests: tests add `sqlite-bundled-jvm` (native library for the host), otherwise the
  driver fails with `UnsatisfiedLinkError: no sqliteJni`.

Robolectric downloads its android-all jar into `maven.repo.local`; the root build points it at the Gradle user home
because `~/.m2` is read-only in the agent environment.

## Sync fixtures on Drive

`:sync:test` runs every `spec/fixtures/sync/*.json` scenario in place (`SyncScenarioTest`, Robolectric) with a real
`ToriStore` + `SyncEngine` per device against `DriveFake`. The fixtures and `known-deviations.json` are unchanged; the
runner adapts them to Drive (doc 38 §11.2):

1. **Accounts.** One `DriveFake` namespace per account: `enableSync account` is Turn-on for that account (its SHA-256
   becomes `driveAccount`), `cloudSwitch` is Turn-on for another namespace (a silent token never switches), and
   `sync.user` is checked as `driveAccount == sha256(user)`.
2. **Cloud expectations** (`entries`, `purged`, `types`): all layout-1 files' envelopes are folded per id with the
   envelope merge, then counted. `purged` also asserts that no file still holds a non-tombstone envelope of the group.
3. **`limit`** (012) = the engine's `applyChunk` in envelopes (and changes per page).
4. **`racedBy`** (037): the racer's whole cycle runs from `beforeNextUpload`; after the last step every raced device runs
   one more sync, then `expected` is checked.
5. **State names:** `iCloudOff` ↔ `Off`, `cloudDeleted` ↔ `DriveDeleted`, `synced` ↔ `Idle` with a `lastSyncAt`.
6. **`upgradeSchema`** (028, 029): a batch file from node `feedfacecafebeef` is put into the account; files with unknown
   types are never covered or deleted.
7. **Clock** (027): `lastServerTime` comes from the fake's `modifiedTime` (the shared clock, without device offsets).
