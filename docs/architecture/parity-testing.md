# Parity testing: shared fixtures for iOS, Android and the backend

Status: **Proposed**.

Related:
- Decision: [native apps, no shared code](memory://7). Domain rules are implemented twice and must behave identically.
- Architecture: [sync.md](sync.md), [scheduler.md](scheduler.md), [backend.md](backend.md).
- Domain: [domain-model.md](../product/domain-model.md) (*Duplicates*, Card invariants).
- Analysis: I9 (published deterministic scheduler with shared test vectors).

## 1. Principle

Behaviour that must be identical across platforms is pinned by **language-neutral JSON fixtures** in `spec/fixtures/`. The iOS and Android test suites (and the backend's, for the parts it implements) run every case.
- **The fixtures are normative.** Where prose in a design doc and a fixture disagree, the fixture wins, and the doc is corrected.
- A change to shared behaviour lands as one pull request that changes the fixtures and both platforms. CI fails if either platform fails any case.
- There are no per-platform skips. A `known-deviations.json` file exists so that a deviation is visible, but its policy is "empty before release".

**What must be covered** (behaviour that must not depend on the platform; analysis §8.7):

| Area | Implemented by | Fixture folder |
|---|---|---|
| Text normalisation (match keys, sentences, URLs) | iOS, Android | `normalization/` |
| Deterministic IDs (UUIDv5) and the namespace | iOS, Android | `ids/` |
| Hybrid logical clock | iOS, Android, backend (skew check) | `hlc/` |
| Field comparator and envelope merge | iOS, Android, backend | `merge/` |
| Sync scenarios: duplicates, deletes, enrichment vs user | iOS, Android | `sync/` |
| Scheduler: replay of ReviewLogs → state, due, stage | iOS, Android | `scheduler/` (case format owned by [scheduler.md](scheduler.md)) |
| Day boundary: "today" from instant + offset (rollover 04:00) | iOS, Android | `scheduler/day-boundary.json` |

Not covered, because these differ by design (analysis §8.7): suggested translations, TTS voices, and UI layout.

## 2. Repository layout

```
spec/
  fixtures/
    README.md                  how to add a case, versioning
    known-deviations.json      [] by policy
    schema/                    JSON Schema for every fixture kind (validated in CI)
      fixture-file.schema.json
      sync-scenario.schema.json
      ...
    normalization/
      match-key-en.json
      match-key-ru.json
      sentence.json
      url.json
    ids/
      uuidv5.json
    hlc/
      local-write.json
      receive.json
    merge/
      field-comparator.json
      envelope.json            deleted / mergedInto / unknown fields
    sync/
      001-concurrent-different-fields.json
      ...
    scheduler/
      day-boundary.json
      fsrs-*.json              defined in scheduler.md
```

**How each suite reads the fixtures** (no copying, one source):
- **iOS:** the folder is added to the test target as a folder reference (bundle resource). Tests are Swift Testing `@Test(arguments:)`, one argument per case ID.
- **Android:** `sourceSets["test"].resources.srcDir("../spec/fixtures")` in Gradle. JUnit 5 `@ParameterizedTest` / `@MethodSource`.
- **Backend:** reads `merge/` and `hlc/receive.json` (skew rule only) the same way.

## 3. Common file format

```json
{
  "kind": "normalization.match-key",
  "specVersion": 1,
  "description": "English match key (domain-model.md, Duplicates)",
  "cases": [
    { "id": "case-fold", "input": { "text": "Take Off", "language": "en" },
      "expected": { "key": "take off" } }
  ]
}
```

- `id` is unique within a file and never reused. Test names print it.
- `specVersion` is bumped when the behaviour of a kind changes. Old versions stay in git history, not in the tree.
- **Time:** instants are `"2026-11-10T07:30:00.000Z"` (UTC, milliseconds), always with `"utcOffsetMinutes": 180` where local time matters. Tests never read the system clock or time zone. Every operation's "now" is given in the case.
- **Numbers:** see §7.

## 4. Normalisation

### 4.1 Match key (`normalization/match-key-*.json`)

Input `{text, language}` → `{key}`. Proposed pipeline (the fixtures decide edge cases):
1. Unicode NFC.
2. Map typographic variants:
   - `’ ‘ ʼ ′` → `'`;
   - `“ ” „ ″` → `"`;
   - `‐ ‑ ‒ – — −` → `-`;
   - NBSP and other space separators → space.
3. Remove default-ignorable characters: ZWSP, ZWJ, ZWNJ, BOM, soft hyphen.
4. Lowercase with the locale-independent Unicode default mapping: Swift `lowercased()`, Kotlin `lowercase()` (root locale). Never use the device locale.
5. Collapse runs of whitespace to one space; trim.
6. Strip leading and trailing characters of Unicode category P* (punctuation), repeatedly; then trim again. Symbols (S*) are kept, e.g. `C++`, `$`.
7. Language-specific step:
   - EN: none.
   - RU (used for Sense translation keys): **pending product decision** on `ё` → `е`. Russian text often omits the dots, so "ёлка" and "елка" would otherwise be two Senses. Flagged to product_writer.

Required cases:

| id | input | expected |
|---|---|---|
| case-fold | `Take Off` | `take off` |
| spaces | `␠␠take␠␠␠off␠` | `take off` |
| nbsp | `take off` | `take off` |
| apostrophe | `don’t` | `don't` |
| quotes-edge | `“mortgage”` | `mortgage` |
| trailing-punct | `well-known.` | `well-known` |
| inner-hyphen-kept | `re-enter` | `re-enter` |
| dash-variant | `re–enter` | `re-enter` |
| nfc | `café` | `café` (diacritics kept) |
| zero-width | `take​off` | `takeoff` |
| soft-hyphen | `mort­gage` | `mortgage` |
| article-kept | `The Bear` | `the bear` |
| inflection-kept | `ran` vs `run` | different keys |
| spelling-kept | `colour` vs `color` | different keys |
| symbols-kept | `C++` | `c++` |
| only-punct | `...` | `""` (the caller rejects an empty key) |
| dotted-capital-i | `İstanbul` | pinned by fixture after both platforms are checked (Swift and Kotlin lowercasing may differ on U+0130). If they differ, both implement the fixture's value explicitly. |
| ru-yo | `Ёлка` (ru) | `ёлка` or `елка`, per the product decision |

### 4.2 Sentence key (`normalization/sentence.json`)

Used for Context duplicates. Steps 1–3 and 5 of §4.1; **case and punctuation are kept**. Cases:
- the same sentence with different quote styles is equal;
- the same sentence with and without a trailing space is equal;
- different capitalisation is **not** equal.

### 4.3 URL key (`normalization/url.json`)

Used for Source IDs.
- Lowercase the scheme and host; IDN hosts become punycode.
- Drop the default port and the fragment.
- Remove the tracking parameters `utm_*`, `fbclid`, `gclid`, `yclid`, `mc_eid`. Keep the order of the other query parameters.
- Keep a trailing slash on the path as is.
- `http` and `https` are **different** keys.

Cases: each rule, plus a URL with no path, and a non-http URL (`app://…`), which is kept as is.

## 5. IDs (`ids/uuidv5.json`)

- **Toriwords namespace UUID:** `6f1c2a4e-3b7d-5e59-9a0c-5d8e7f2b1c34`. **Fixed for ever once v1 ships**; changing it would change every deterministic ID.
- Cases: name → UUID for each pattern in [sync.md](sync.md) §4 (`pair:ru:en`, `card:<entryId>:recognition`, `source:<urlKey>`, `entrytag:<entryId>:<tagId>`, `settings`). Plus UUID byte-order comparison cases for "smallest ID wins".

## 6. Clock and merge

### 6.1 `hlc/local-write.json`, `hlc/receive.json`

Input: state `{ms, counter}`, node, physical time, and for receive the remote clock string. Expected: the new state and the emitted clock string. Cases:
- physical time ahead;
- same millisecond;
- physical clock went backwards;
- counter overflow;
- remote ahead, remote behind, remote equal;
- **remote more than 24 h ahead** (not adopted);
- server skew check (more than 1 h ahead → `clock_skew`).

### 6.2 `merge/field-comparator.json`

Input: two `{v, c, u}`. Expected: the winner. Cases:
- rank 1 beats rank 0 even with an older clock;
- same rank, later clock wins;
- same rank, same ms, counter decides;
- same ms and counter, node decides;
- identical clocks.

### 6.3 `merge/envelope.json`

Input: two envelopes of the same record. Expected: the merged envelope. Cases:
- `deleted` OR;
- a tombstone drops the fields;
- `mergedInto`: null vs value, value vs value (smaller wins);
- an unknown field present on one side only is kept;
- disjoint field sets are unioned;
- the server-side merge of a partial push (subset of fields) equals the full merge.

## 7. Scheduler conventions (`scheduler/`)

The case format, parameters and algorithm are defined in [scheduler.md](scheduler.md). This document fixes only the conventions every scheduler fixture follows:
- **Input:** Settings (target retention, parameter set, scheduler version) and a list of ReviewLogs `{id, reviewedAt, utcOffsetMinutes, rating, kind?}` in arbitrary order. The runner sorts them by `(reviewedAt, id)`, so sort order is tested too.
- **Expected after each log and at the end:** stage, `due` (instant), interval in days. These are user-visible values and must match **exactly**. Internal floating-point state (e.g. stability, difficulty) is compared with a relative tolerance of `1e-9`, because Swift and Kotlin may call different `exp`/`pow` implementations that differ in the last bit.
- **Rounding** of floating-point values into user-visible integers is specified in [scheduler.md](scheduler.md) and must be robust to that last-bit difference. Fixtures include values near rounding boundaries.
- **Fuzz** is seeded from the Card ID and the review count ([scheduler.md](scheduler.md) §9). After an Entry merge, the seed uses the **canonical** Card ID ([sync.md](sync.md) §7.3), so merged history replays identically everywhere.
- **Generator:** expected values are produced by `tools/fixtures/` (a dev tool, not app code). It wraps the pinned reference FSRS-6 implementation (py-fsrs or fsrs-rs, [scheduler.md](scheduler.md) §2) with the Toriwords rules: whole days, `dayNumber`, deterministic fuzz, stage thresholds. Generated files are committed. A regenerated file that differs from the committed one fails CI until the change is reviewed.
- **`day-boundary.json`:** `(instant, utcOffsetMinutes)` → review day, per the `dayNumber` formula in [scheduler.md](scheduler.md) §4 (rollover at 04:00 local). Cases:
  - just before and just after the rollover hour;
  - offset changes across days (travel);
  - DST transitions;
  - a review stored with offset +3 and replayed on a device at −5, which must give the same day, because the stored offset wins.

## 8. Sync scenarios (`sync/*.json`)

### 8.1 Model

A scenario runs the real client sync engine in-process for several **simulated devices**, plus a **hub** replica.
- The hub stands in for the server. It applies only the generic envelope merge (§6.3), which the client already implements for incoming records, so no fake server logic is written twice.
- Device clocks and IDs come from the scenario, so the result is exact.

```json
{
  "kind": "sync.scenario",
  "specVersion": 1,
  "id": "008-same-word-two-devices",
  "description": "Same word captured offline on phone and tablet, then both sync",
  "devices": { "A": { "deviceId": "0192…a1" }, "B": { "deviceId": "0192…b2" } },
  "steps": [
    { "device": "A", "now": "2026-11-10T08:00:00.000Z", "op": "capture",
      "args": { "text": "mortgage", "translation": "ипотека", "sentence": "…", "ids": { "entry": "0192…01", "sense": "0192…02", "context": "0192…03" } } },
    { "device": "B", "now": "2026-11-10T08:05:00.000Z", "op": "capture",
      "args": { "text": "Mortgage", "translation": "ипотека", "sentence": "…other…", "ids": { "entry": "0192…04", "sense": "0192…05", "context": "0192…06" } } },
    { "device": "B", "now": "2026-11-10T09:00:00.000Z", "op": "review",
      "args": { "card": "recognition", "entryText": "Mortgage", "rating": "good", "utcOffsetMinutes": 180, "id": "0192…07" } },
    { "device": "A", "op": "sync" },
    { "device": "B", "op": "sync" },
    { "device": "A", "op": "sync" }
  ],
  "expected": {
    "allDevicesEqual": true,
    "view": {
      "entries": [ { "id": "0192…01", "text": "mortgage", "senses": ["ипотека"],
                    "contexts": 2, "cards": { "recognition": { "reviews": 1, "stage": "learning" } } } ],
      "mergedInto": { "0192…04": "0192…01" }
    }
  }
}
```

- **`op` vocabulary** (the test harness maps each op to the platform's app-level API, not to raw database writes): `capture`, `editField`, `enrich`, `review`, `exclude`, `resume`, `delete`, `tag`, `untag`, `mergeByEdit`, `signIn`, `sync`, `pullOnly`, `pushOnly`, `setSettings`, `upgradeSchema`.
- **`expected.view`** is a canonical, sorted projection of what the user sees: live Entries with their Senses, Contexts, Tags and Card summaries. Optionally it also includes the survivor's stored fields with clocks, to check byte-identity.
- `allDevicesEqual` asserts that every device's view equals the hub's after the final sync.

### 8.2 Required scenarios

| # | Scenario | Asserts |
|---|---|---|
| 001 | Concurrent edits of different fields of one Entry | Both kept |
| 002 | Concurrent edits of the same field | Later clock wins, no prompt |
| 003 | User edits translation on A; B's enrichment writes the same field later | User value wins (rank) |
| 004 | User edits translation on A; B's enrichment fills the empty definition | Both kept |
| 005 | User empties an enriched field, enrichment runs again | Stays empty (rank 1 is never overwritten by enrichment) |
| 006 | Delete on A, offline edit on B | Deleted everywhere, payload dropped |
| 007 | Delete on A, offline reviews on B | Deleted, reviews purged |
| 008 | Same word captured offline on two devices (example above) | One Entry, smallest ID survives, Contexts united, equal Senses collapsed, both ReviewLogs on one Card, Card state = replay of the merged log |
| 009 | Three duplicates merged in two steps on different devices | Converges to the smallest ID, no chains left unresolved |
| 010 | Edit of a loser after it was merged elsewhere | Newer user value reaches the survivor |
| 011 | Data created before sign-in on two devices, then both sign in | Same as 008, plus Settings and LanguagePair collapse |
| 012 | User edits text to collide with another Entry (`mergeByEdit`) | Same survivor rule |
| 013 | LanguagePair auto-created on both devices | One pair (deterministic ID) |
| 014 | Card created on both devices for the same Entry and direction | One Card |
| 015 | Untag on A, re-tag on B | Final `present` per LWW |
| 016 | Same URL captured on two devices | One Source |
| 017 | An older client edits a record that has a field it does not know | The unknown field survives |
| 018 | The same records pulled in different orders and page splits | Identical result |
| 019 | Tombstone arrives before the record it deletes | Record never appears |
| 020 | A child arrives for an already-deleted Entry | Dropped |
| 021 | Reviews on two devices in different time zones, same Card | Replay uses the stored offsets; same due date on both |
| 022 | Settings change (target retention) on A while B reviews offline | Both rebuild derived state; same due dates |
| 023 | Remote clock 3 days ahead | Not adopted into the local HLC; its fields still win |

## 9. Process

- New shared behaviour starts with fixtures, then both implementations.
- A bug found on one platform gets a fixture first. The other platform then proves it does not have the same bug.
- CI runs the iOS and Android suites on every change under `spec/`, `ios/` or `android/`. Backend CI runs on changes under `spec/fixtures/merge`, `spec/fixtures/hlc` or `backend/`.
- The fixture JSON is validated against `spec/fixtures/schema/` in CI before the suites run.
