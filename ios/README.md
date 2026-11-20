# ToriWords for iOS

The native iOS app (SwiftUI, iOS 18+) and its Swift package **ToriKit**.

## Prerequisites

| Tool | Version | Pinned in |
|---|---|---|
| Xcode | 27.x (iOS 27 SDK; deployment target iOS 18) | `.github/workflows/ios.yml` (`XCODE_VERSION`) |
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

## App icon

- **Asset:** `Resources/Assets.xcassets/AppIcon.appiconset` has single-size 1024×1024 images: `AppIcon.png` (light, opaque,
  no alpha channel, as App Store Connect requires) and `AppIcon-dark.png` (dark, transparent background). iOS derives
  the tinted and clear looks from these.
- **Sources:** `Resources/AppIcon/AppIcon.svg` and `AppIcon-dark.svg`. They are not bundled. Edit the SVG, then re-render
  with a renderer that supports SVG masks (librsvg, a browser):

  ```sh
  cd ios/Resources
  rsvg-convert -w 1024 -h 1024 AppIcon/AppIcon.svg \
    | magick - -background white -alpha remove -alpha off Assets.xcassets/AppIcon.appiconset/AppIcon.png
  rsvg-convert -w 1024 -h 1024 AppIcon/AppIcon-dark.svg -o Assets.xcassets/AppIcon.appiconset/AppIcon-dark.png
  ```

## Configuration

All build settings live in `Config/Shared.xcconfig`. It holds no secrets.

| Key | Meaning |
|---|---|
| `DEVELOPMENT_TEAM` | Your Apple team ID, needed for device builds. |
| `TORI_APP_GROUP_ID` | `group.com.toriwords.app`. Shared by the app, Share Extension and widget. |
| `TORI_BG_REFRESH_TASK_ID` | `com.toriwords.app.refresh` (`BGAppRefreshTask`). |
| `TORI_URL_SCHEME` | `toriwords`, for `toriwords://review` and `toriwords://add?text=…`. |

There is no backend: sync uses the iCloud private database (CloudKit container `iCloud.com.toriwords.app`).

### Bundle IDs and capabilities

| Target | Bundle ID | Notes |
|---|---|---|
| `Toriwords` (app) | `com.toriwords.app` | Entitlements: App Group, iCloud (CloudKit, container `iCloud.com.toriwords.app`). Background fetch (`BGTaskSchedulerPermittedIdentifiers`). URL scheme `toriwords`. |
| `ToriwordsShare` | `com.toriwords.app.share` | Share Extension (text, one web URL, Safari web page with `ExtensionPreprocessing.js`). Entitlement: App Group. |
| `ToriwordsWidget` | `com.toriwords.app.widget` | WidgetKit (small, medium, lock-screen circular and rectangular). Entitlement: App Group. |

All three targets: iOS 18.0, Swift 6 language mode, `CFBundleLocalizations` en + ru. The app sets
`ITSAppUsesNonExemptEncryption = NO` and is portrait-only on iPhone (all orientations on iPad).

### Signing

CI builds unsigned (`CODE_SIGNING_ALLOWED=NO`). For a device:

- Set `DEVELOPMENT_TEAM`.
- Let Xcode manage signing.
- Register the App Group `group.com.toriwords.app` and the iCloud container `iCloud.com.toriwords.app` (CloudKit) for the app ID.

Without the App Group entitlement, `AppGroup.shared` is nil. Sharing, the widget snapshot and the vocab index are then
off, and the app still runs.

### Free Apple ID (Personal Team)

The `Toriwords-Personal` scheme builds the `Personal` configuration (`Config/Personal.xcconfig`) for a free Apple ID.
A Personal Team cannot sign iCloud or App Groups, so that build has no entitlements, no iCloud sync (the Settings
row shows "—"). Share capture and the widget need the App Group, so in this build ToriWords is not listed in Share
(the extension's activation rule is `FALSEPREDICATE`), Home does not mention it, and the widget offers no sizes (not
in the widget gallery). Words, review, speech, translation and the
dictionary work. It installs next to the full app under its own bundle ID, and Xcode must reinstall it every 7 days.

1. Xcode → Settings → Accounts: add your Apple ID.
2. Create `Config/Personal.local.xcconfig` (gitignored):

   ```
   DEVELOPMENT_TEAM = <your Personal Team ID>
   TORI_BUNDLE_ID = com.<you>.toriwords
   ```

3. `tools/dictionary/fetch.sh` (full dictionary; without it the build uses the sample), then `tuist generate`.
4. Run the `Toriwords-Personal` scheme on the iPhone. On the phone: turn on Developer Mode, and after the first install
   trust the developer profile (Settings → General → VPN & Device Management).

## Module map

```
App (Toriwords)      SwiftUI screens, AppEnvironment (composition root), Router, Platform/ (sync, reminders, config)
ShareExtension       capture sheet → App Group inbox (no database access)
WidgetExtension      reads widget-snapshot.json from the App Group
ToriKit/
  ToriCore           pure domain: IDs, HLC, merge, text keys, capture rules, FSRS scheduler, daily queue, widget snapshot,
                     reminder plan
  ToriShared         App Group layout, inbox files, vocab index, deep links, Darwin notification
  ToriDictionary     read-only dictionary.sqlite, read in place from the app bundle
  ToriStore          user.sqlite (GRDB): records, outbox, sync apply, queries, backup
  ToriSync           SyncEngine, CloudDatabase protocol, CloudKit adapter (iCloud private database)
  ToriEnrichment     on-device translation, dictionary lookup, enrichment orchestrator, speech
  ToriUI             design tokens and shared SwiftUI components
```

Allowed dependencies are declared in `ToriKit/Package.swift`. The extensions link only ToriCore,
ToriShared, ToriDictionary and ToriUI.

## Specs and fixtures

- Parity fixtures shared with Android: `spec/fixtures/`. See `spec/fixtures/README.md`. That covers normalization, IDs,
  HLC, merge, capture, the scheduler and the multi-device `sync/` scenarios. `known-deviations.json` must be `[]`.
- CI workflows: `.github/workflows/toriKit-linux.yml`, `tools.yml` and `ios.yml`.
