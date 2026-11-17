# ToriWords for iOS

The native iOS app (SwiftUI, iOS 26+) and its Swift package **ToriKit**. The architecture spec is doc 36. The product
spec is doc 34 and the UI spec is doc 35.

## Prerequisites

| Tool | Version | Pinned in |
|---|---|---|
| Xcode | 26.x or later with the iOS 26 SDK (CI uses 26.4) | `.github/workflows/ios.yml` (`XCODE_VERSION`) |
| Tuist | see file | `ios/.tuist-version` |
| Swift on Linux (ToriKit tests only) | see file | repo-root `.swift-version` |
| uv + Python 3.12 (fixtures, dictionary tools) | — | `tools/*/pyproject.toml` |

Install Tuist with [mise](https://mise.jdx.dev): `mise use tuist@$(cat ios/.tuist-version)`.

## Generate and run the app

```sh
cd ios
tuist install            # resolves ToriKit + GRDB (Tuist/Package.swift)
tuist generate           # writes and opens Toriwords.xcworkspace
```

Run the `Toriwords` scheme on a simulator. The generated project and workspace are not committed. Regenerate after
changing `Project.swift`, `Tuist/Package.swift` or adding files.

Command-line build (what CI does):

```sh
xcodebuild build -workspace Toriwords.xcworkspace -scheme Toriwords -configuration Debug \
  -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO
```

## ToriKit tests

On a Mac (iOS Simulator, all test targets including `ToriUITests`):

```sh
cd ios/ToriKit
xcodebuild test -scheme ToriKit-Package -destination "platform=iOS Simulator,name=iPhone 17"
```

On Linux: everything except Apple-only code is behind `#if canImport(...)`. Install the toolchain with
[swiftly](https://www.swift.org/install/linux/); it reads `.swift-version`.

```sh
swiftly install --use                        # once, from the repo root
source ~/.local/share/swiftly/env.sh         # per shell
cd ios/ToriKit && swift test
```

The parity fixtures are found from the test sources' location. Set `TORI_FIXTURES=/path/to/spec/fixtures` to use
another checkout. On the simulator, pass it as `TEST_RUNNER_TORI_FIXTURES`.

Fixture and dictionary tools have their own tests (CI: `tools.yml`):

```sh
cd tools/fixtures && uv run python validate.py && uv run pytest
cd tools/dictionary && uv run pytest
```

## Dictionary

The offline EN→RU dictionary `dictionary.sqlite` (about 60 MiB, CC BY-SA 4.0) is **not** in git.

- **Sample:** `ios/Resources/dictionary-sample.sqlite` is committed. It is a few hundred headwords from the same build,
  with the same schema. Debug builds, tests and CI work with it.
- **Full file:** run `tools/dictionary/fetch.sh` before a Release build. It downloads the GitHub Release asset named in
  `tools/dictionary/release.json` to `ios/Resources/dictionary.sqlite`, then checks it against the committed
  `dictionary.sqlite.sha256`. On a mismatch it deletes the file and fails.
- **Release hand-off:** `tools/dictionary` builds the file and the owner publishes it as a GitHub Release
  (`gh release create dictionary-<ver> …`). The owner then commits `release.json`, `dictionary.sqlite.sha256`,
  `build-report.md` and the refreshed sample. See `tools/dictionary/README.md`.
- **Rebuild:** `cd tools/dictionary && uv run python -m toridict build`. It downloads the pinned Wiktionary dumps
  (several GB, cached) and gives the same bytes for the same inputs.

CI downloads the full file only when the Release asset exists. Otherwise it builds Debug with the sample.

## Configuration

All build settings live in `Config/Shared.xcconfig`. It holds no secrets.

| Key | Meaning |
|---|---|
| `DEVELOPMENT_TEAM` | Your Apple team ID, needed for device builds. |
| `TORI_APP_GROUP_ID` | `group.com.toriwords.app`. Shared by the app, Share Extension and widget. |
| `TORI_BG_REFRESH_TASK_ID` | `com.toriwords.app.refresh` (`BGAppRefreshTask`, doc 36 §10.4). |
| `TORI_URL_SCHEME` | `toriwords`, for `toriwords://review` and `toriwords://add?text=…`. |
| `TORI_API_BASE_URL` | Backend base URL, **https only**. Empty means sync is off and the app is local-only. |
| `TORI_GOOGLE_CLIENT_ID` / `TORI_GOOGLE_REVERSED_CLIENT_ID` | iOS OAuth client ID and its reversed form. While it contains `REPLACE_ME`, Google sign-in is hidden. |

`//` starts a comment in an xcconfig file, so write URLs with an empty variable between the slashes:

```
TORI_API_BASE_URL = https:/$()/api.toriwords.app
```

The app reads these values from Info.plist keys (`ToriAPIBaseURL`, `ToriGoogleClientID`,
`ToriGoogleReversedClientID`) that `Project.swift` maps to the xcconfig values.

### Bundle IDs and capabilities

| Target | Bundle ID | Notes |
|---|---|---|
| `Toriwords` (app) | `com.toriwords.app` | App Group, Sign in with Apple, background fetch (`BGTaskSchedulerPermittedIdentifiers`), URL scheme |
| `ToriwordsShare` | `com.toriwords.app.share` | Share Extension, App Group |
| `ToriwordsWidget` | `com.toriwords.app.widget` | WidgetKit, App Group |

### Signing

CI builds unsigned (`CODE_SIGNING_ALLOWED=NO`). For a device:

- Set `DEVELOPMENT_TEAM`.
- Let Xcode manage signing.
- Register the App Group `group.com.toriwords.app` and Sign in with Apple for the app ID.

Without the App Group entitlement, `AppGroup.shared` is nil. Sharing, the widget snapshot and the vocab index are then
off, and the app still runs.

## Module map

```
App (Toriwords)      SwiftUI screens, AppEnvironment (composition root), Router, Platform/ (sync, reminders, config)
ShareExtension       capture sheet → App Group inbox (no database access)
WidgetExtension      reads widget-snapshot.json from the App Group
ToriKit/
  ToriCore           pure domain: IDs, HLC, merge, text keys, capture rules, FSRS scheduler, daily queue, widget snapshot,
                     reminder plan
  ToriShared         App Group layout, inbox files, vocab index, deep links, Darwin notification
  ToriDictionary     read-only dictionary.sqlite + installer
  ToriStore          user.sqlite (GRDB): records, outbox, sync apply, queries, backup
  ToriSync           HTTP client, sessions (Keychain), SyncEngine, Apple/Google sign-in
  ToriEnrichment     on-device translation, dictionary lookup, enrichment orchestrator, speech
  ToriUI             design tokens and shared SwiftUI components
```

Allowed dependencies are declared in `ToriKit/Package.swift` (doc 36 §2.3). The extensions link only ToriCore,
ToriShared, ToriDictionary and ToriUI.

## Specs and fixtures

- Specs: docs 34 (product), 35 (UI) and 36 (architecture) in the project workspace.
- Parity fixtures shared with Android: `spec/fixtures/`. See `spec/fixtures/README.md`. That covers normalization, IDs,
  HLC, merge, capture, the scheduler and the multi-device `sync/` scenarios. `known-deviations.json` must be `[]`.
- CI workflows: `.github/workflows/toriKit-linux.yml`, `tools.yml` and `ios.yml`.
