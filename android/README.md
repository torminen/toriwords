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
