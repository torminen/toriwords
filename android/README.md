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
