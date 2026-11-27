# ToriWords for iOS: specification

This folder is the canonical specification of the ToriWords iOS app (v1). ToriWords is a personal vocabulary app: you save English words and phrases with their meanings and the sentences where you met them, and you review them with spaced repetition (FSRS-6).

The spec describes the app as it is built in `ios/`, plus the plans for v1. Where the app does not yet do what is planned, the rule says **Not yet implemented** or **Partly implemented** inline. Things deliberately left out of v1 are listed in [product.md → Later (not in v1)](product.md#3-later-not-in-v1).

## Scope

- **Platform:** iOS 18 and later; a few visuals (Liquid Glass) need iOS 26. Swift 6 and SwiftUI, with the logic in the ToriKit Swift package. Build and run instructions: [ios/README.md](../README.md).
- **Template:** the iOS app is the reference for behaviour and UI for both platforms. The Android app matches it wherever its platform allows. Every deliberate Android difference, with its reason, is listed in [android/docs/ios-differences.md](../../android/docs/ios-differences.md). That file is the only list of platform differences; this folder does not keep a second one.
- **No account and no server.** All data lives on the phone. Sync between the user's Apple devices goes through their iCloud private database. iPhone and Android do not sync with each other; the JSON backup moves words between them.
- **Shared with Android:** only the parity fixtures in `fixtures/` (normative test data for the text rules, IDs, clock, merge, scheduler and sync) and the dictionary built by `tools/dictionary/`. Where this spec and a fixture disagree, the fixture wins. Where this spec and the iOS code disagree, the code wins and this spec is fixed.
- **Shared rules:** rules that are the same on both platforms (envelope, IDs, clock, merge, deletion, scheduler, keys and folds, capture text rules) are written in the same words here and in `android/docs/`. A change to a shared rule updates both folders.
- **Languages:** v1 has one language pair: native Russian, learning English. The app UI is in English and Russian. This spec is written in English.

## Files

| File | What it covers |
|---|---|
| [product.md](product.md) | Goals and principles, scope and the "later" list, every feature with its behaviour rules and edge cases, cross-cutting rules |
| [domain.md](domain.md) | The vocabulary model: words, meanings, sentences, sources, cards, reviews, tags, devices and settings; states, invariants, normalisation and duplicates, merge requirements |
| [ui.md](ui.md) | Navigation map, per-screen rules, motion and haptics, accessibility (VoiceOver, Reduce Motion), branding and theme, widget |
| [copy.md](copy.md) | English and Russian UI strings of the app, the Share Extension and the widget |
| [architecture.md](architecture.md) | System overview, stack, targets and App Group, modules, concurrency, start-up and restore, launch animation and haptics, background refresh, deep links, observability, performance, repository layout, CI and release |
| [data-model.md](data-model.md) | Local database schema, keys and folds, integrity rules, migrations, settings storage, export and restore format, device backup, Remove all data |
| [capture-and-enrichment.md](capture-and-enrichment.md) | Capture through the Share Extension, capture text rules, the App Group inbox, the bundled dictionary, enrichment and Apple Translation, pronunciation (TTS) |
| [scheduler.md](scheduler.md) | Grading, the review day, FSRS-6, replay, the daily queue and catch-up, review sessions and practice, stats, widget snapshot and timeline, reminders |
| [sync.md](sync.md) | Sync records, envelope, IDs, hybrid logical clock, outbox, merge and deletion, schema evolution, CloudKit transport, errors, status, triggers, iCloud account and user actions |
| [testing.md](testing.md) | How iOS runs the parity fixtures, sync scenarios on the in-memory cloud, iOS-only tests, CI |

## Reading order

1. Product and UI: [product.md](product.md) → [domain.md](domain.md) → [ui.md](ui.md) → [copy.md](copy.md) → [android/docs/ios-differences.md](../../android/docs/ios-differences.md).
2. Engineering: [architecture.md](architecture.md) → [data-model.md](data-model.md) → [capture-and-enrichment.md](capture-and-enrichment.md) → [scheduler.md](scheduler.md) → [sync.md](sync.md) → [testing.md](testing.md).

Product files describe behaviour only and link to the engineering files for mechanisms. Each rule is written once, in its owner file. Other files link to it.

## Changing the spec

Changes to iOS behaviour are made in these files, in the same pull request as the code where possible. A planned change that is not built yet is added with a **Not yet implemented** note; the note is removed when the code lands.

## Glossary

| UI word | Model term | Meaning |
|---|---|---|
| word / phrase | Entry | An English item the user is learning |
| meaning | Sense | One translation (and optional definition and part of speech) of an Entry |
| sentence | Context | A real sentence where the user met the Entry (the word highlighted when found), or a source-only record with no sentence |
| source | Source | Where a sentence came from: a web page, an app, a typed title, or a related-word suggestion |
| card | Card | One reviewable prompt of an Entry (recognition, recall, cloze) |
| review | ReviewLog | One graded answer to a card |
| review day | — | The local day that starts at 04:00 |

## Open questions

Any remaining open questions are listed at the end of the file they belong to.
