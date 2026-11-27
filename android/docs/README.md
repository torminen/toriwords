# ToriWords for Android: specification

This folder is the canonical specification of the ToriWords Android app (v1). ToriWords is a personal vocabulary app: you save English words and phrases with their meanings and the sentences where you met them, and you review them with spaced repetition (FSRS-6).

## Scope

- **Platform:** Android 12 (API 31) and later; target and compile SDK 37. Kotlin and Jetpack Compose with Material 3. No code is shared with iOS.
- **Template:** the iOS app on `main` (`ios/`) is the reference for behaviour and UI. Android matches it wherever the platform allows. Every deliberate difference, with its reason, is listed in [ios-differences.md](ios-differences.md).
- **No account and no server.** All data lives on the phone. Sync between the user's Android devices is optional and goes through the app data folder in their Google Drive. Android and iPhone do not sync with each other; the JSON backup moves words between them.
- **Shared with iOS:** only the parity fixtures in `spec/fixtures/` (normative test data for the text rules, IDs, clock, merge, scheduler and sync) and the dictionary built by `tools/dictionary/`. Where this spec and a fixture disagree, the fixture wins.
- **Languages:** v1 has one language pair: native Russian, learning English. The app UI is in English and Russian. This spec is written in English.

## Files

| File | What it covers |
|---|---|
| [product.md](product.md) | Goals and principles, scope and the "later" list, every feature with its behaviour rules and edge cases, cross-cutting rules |
| [domain.md](domain.md) | The vocabulary model: words, meanings, sentences, sources, cards, reviews, tags, devices and settings; states, invariants, normalisation and duplicates, merge requirements |
| [ui.md](ui.md) | Navigation map, per-screen Material 3 rules, Back and predictive back, motion and haptics (what the user sees and feels), accessibility, branding and theme |
| [copy.md](copy.md) | English and Russian UI strings |
| [ios-differences.md](ios-differences.md) | Every Android-vs-iOS difference and why |
| [architecture.md](architecture.md) | System overview, stack, permissions, manifest components, modules, concurrency, start-up and restore, launch animation and haptics mechanism, background work, observability, performance, repository layout, CI and release |
| [data-model.md](data-model.md) | Local database schema, keys and folds, integrity rules, migrations, settings storage, export and restore format, OS backup, Remove all data |
| [capture-and-enrichment.md](capture-and-enrichment.md) | Capture from text selection and Share, capture text rules, the bundled dictionary, enrichment and on-device translation (ML Kit), pronunciation (TTS) |
| [scheduler.md](scheduler.md) | Grading, the review day, FSRS-6, replay, the daily queue and catch-up, review sessions and practice, stats, widget snapshot, reminders |
| [sync.md](sync.md) | Sync records, envelope, IDs, hybrid logical clock, outbox, merge and deletion, schema evolution, errors, status, triggers, Google Drive authorization and transport |
| [testing.md](testing.md) | How Android runs the parity fixtures (JVM, Robolectric, instrumented), the Drive fake for sync scenarios, Android-only tests |

## Reading order

1. Product and UI: [product.md](product.md) → [domain.md](domain.md) → [ui.md](ui.md) → [copy.md](copy.md) → [ios-differences.md](ios-differences.md).
2. Engineering: [architecture.md](architecture.md) → [data-model.md](data-model.md) → [capture-and-enrichment.md](capture-and-enrichment.md) → [scheduler.md](scheduler.md) → [sync.md](sync.md) → [testing.md](testing.md).

Product files describe behaviour only and link to the engineering files for mechanisms. Each rule is written once, in its owner file. Other files link to it.

## Glossary

| UI word | Model term | Meaning |
|---|---|---|
| word / phrase | Entry | An English item the user is learning |
| meaning | Sense | One translation (and optional definition and part of speech) of an Entry |
| sentence | Context | A real sentence where the user met the Entry, with the word highlighted |
| source | Source | Where a sentence came from: a web page, an app, a typed title, or a related-word suggestion |
| card | Card | One reviewable prompt of an Entry (recognition, recall, cloze) |
| review | ReviewLog | One graded answer to a card |
| review day | — | The local day that starts at 04:00 |

## Open questions

Any remaining open questions are listed at the end of the file they belong to.
