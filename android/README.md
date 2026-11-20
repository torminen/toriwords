# Toriwords Android

Modules: `core` (pure Kotlin port of ToriCore: IDs, text keys, HLC, merge, FSRS), `store` (Room port of ToriStore),
`sync` (Drive sync engine), `app` (Compose UI).

## Build & test

```sh
. /home/unc/.cache/toolchain/env.sh   # JDK, Android SDK, Gradle caches (agent environment)
cd android
./gradlew :core:test :store:test :sync:test :app:testDebugUnitTest   # JVM unit tests (store on Robolectric, in-memory DB)
./gradlew :sync:testDebugUnitTest --tests '*OkHttpDriveApi*'           # one class (`--tests` needs the variant task)
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

## Google Drive OAuth setup

Drive sync uses the `drive.appdata` scope through Play services `AuthorizationClient`; there is no client secret in the
app. Each developer build needs an OAuth client registered for its signing key:

1. In the [Google Cloud console](https://console.cloud.google.com/), create (or pick) a project and enable the
   **Google Drive API**.
2. **OAuth consent screen:** user type External, add the scope `https://www.googleapis.com/auth/drive.appdata`, and add
   your test Google accounts as test users while the app is in testing.
3. **Credentials → Create credentials → OAuth client ID → Android:** package name `com.toriwords`, SHA-1 of the debug
   keystore:
   ```sh
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
   ```
   (Release builds need a second Android client with the Play app-signing SHA-1.)
4. `./gradlew :app:assembleDebug`, install the APK on two devices signed in with the same Google account, open
   Settings → Google Drive sync on each and tap **Turn on Google Drive sync**.

Without a matching OAuth client the consent sheet fails and sync stays off.

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
