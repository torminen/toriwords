# Parity fixtures

Language-neutral JSON cases that pin every behaviour iOS, Android and the backend must share
(doc 36 §15, §22; Android runner rules doc 38 §15). **Fixtures are normative:** if a doc and a
fixture disagree, the fixture wins and the doc is fixed.

## Layout

| Folder | Files | What it pins |
|---|---|---|
| `normalization/` | `match-key`, `translation-key`, `sentence-key`, `tag-key`, `search-fold`, `url-key`, `source-key`, `text-order` | Text keys (doc 36 §15.1), BINARY text order and prefix ranges (§4.1, §8.2) |
| `ids/` | `uuid-v5`, `uuid-v7`, `byte-order` | Deterministic IDs and their names, UUIDv7 layout, unsigned byte order (§11.2) |
| `hlc/` | `local-write`, `receive`, `clock-ahead` | HLC local write, receive (> 24 h not adopted), server 1 h skew, clock-ahead recovery (§11.3, §11.5) |
| `merge/` | `field-comparator`, `envelope` | Comparator and envelope merge incl. partial push (§11.3, §22.1) |
| `capture/` | `clean`, `extract`, `typed-highlight` | Capture text rules (§5.2) |
| `scheduler/` | `fsrs-step`, `fsrs-replay`, `day-boundary`, `queue-*`, `snapshot` | FSRS-6, replay, 04:00 day, daily queue, widget snapshot (§7, §10.1). **Generated**, see below |
| `sync/` | `001–034` | Multi-device scenarios (§11–12) — added with the sync step |
| `schema/` | `<kind>.schema.json` | JSON Schema 2020-12, one per fixture kind |
| `known-deviations.json` | | Must be `[]` before release; no per-platform skips |

## Case format

Every file is an object `{ "kind", "source", …file-level inputs…, "cases": [...] }`.
`kind` selects the schema (`schema/<kind>.schema.json`); `source` cites the doc sections.
Every case has a stable `id` (never renumber or reuse), its inputs, an `expected` value and an optional `note`.
Runners run one test argument per case id and print it in the test name.

- Time is always explicit (`now`, `reviewedAt`, `utcOffsetMin`); tests never read the clock or time zone.
- Instants are Unix ms (UTC), offsets minutes east of UTC, days are §7.2 day numbers.
- Comparison: integers (days, intervals, counts, stage, offsets) exactly; `stability`/`difficulty` within 1e-9 relative.
- UTF-16 offsets/lengths (highlights) are UTF-16 code units; "characters" in capture lengths (5,000, 500) are Unicode code points.

## Rules for the text functions (explicit lists, never a Unicode property lookup)

- **Quote/dash/space mapping (match key step 2):** `’ ‘ ʼ ′` (U+2019, U+2018, U+02BC, U+2032) → `'`; `“ ” „ ″` (U+201C, U+201D, U+201E, U+2033) → `"`;
  `‐ ‑ ‒ – — −` (U+2010, U+2011, U+2012, U+2013, U+2014, U+2212) → `-`;
  space separators U+00A0, U+1680, U+2000–U+200A, U+202F, U+205F, U+3000 → U+0020.
- **Default-ignorables removed (step 3):** U+00AD soft hyphen, U+200B ZWSP, U+200C ZWNJ, U+200D ZWJ, U+2060 word joiner, U+FEFF BOM. Exactly this list.
- **Whitespace** (collapse, trim, tokens): U+0009–U+000D, U+0020, U+0085, U+2028, U+2029.
- **Lowercase:** per code point full default mapping (Unicode `SpecialCasing` unconditional + `UnicodeData`), no locale and no context: `İ` → `i̇` (U+0069 U+0307), `Σ` → `σ` always (never final `ς`). Kotlin's `lowercase()` applies final sigma: map per code point instead.
- **ё/Ё → е/Е** in every key that folds ё (the sentence key keeps case, so `Ё` → `Е`).
- **Punctuation** = general category P*; **letters/numbers** = L*/N*. Fixtures only use characters whose categories are stable since Unicode 13.
- **Latin letter** (capture reject rule): A–Z, a–z, U+00C0–U+024F except U+00D7 and U+00F7, U+1E00–U+1EFF.
- **URL key:** explicit split `scheme ':' '//' [userinfo '@'] host [':' port] path ['?' query] ['#' fragment]` — never a platform URL parser
  (they differ in IDN, percent-encoding and port handling). Punycode = RFC 3492 per host label that contains non-ASCII, after lowercasing.
  Parameter names are matched case-sensitively; an empty query after removal drops the `?`.
- **Capture closers** after `. ! ? …`: `" ' ” ’ » ) ]`.
- **Capture speaker label** (per line): optional spaces/tabs, 1–3 words separated by spaces/tabs, `:`, then a "space" or the
  line end; trailing spaces/tabs are removed too. A word is a run of code points that are neither `:` nor "space";
  "space" = the whitespace list plus the space separators above.
- **Capture annotations:** a left-to-right scan; `[` or `(` followed by one or more letters (L*) or U+0020 and the matching
  `]` / `)` is removed. A removed span is not rescanned; anything else is kept as is.

## Unicode ≤ 13

Fixtures may contain only code points assigned in Unicode 13.0 (Android API 31's ICU floor). `tools/fixtures/validate.py`
rejects anything else using the pinned table `tools/fixtures/data/assigned-13.0.txt` (derived from UnicodeData.txt 13.0.0
by `derive_unicode.py`).

## Process

- Shared behaviour starts with a fixture, then the implementations. A bug found on one platform gets a fixture first.
- Hand-written folders (`normalization`, `ids`, `hlc`, `merge`, `capture`) are edited by hand; `tools/fixtures/tests` cross-checks
  each case against the Python reference in `tools/fixtures/torifix/` so a typo in either side fails.
- `scheduler/` is generated: change `tools/fixtures/torifix/scheduler.py` or `generate.py`, then
  `cd tools/fixtures && uv run python generate.py`. Generation is deterministic; the test suite fails if a committed file is stale.
- FSRS-6 defaults and formulas are checked against the pinned py-fsrs release (`tools/fixtures/pyproject.toml`, AQ-17).
- CI: `cd tools/fixtures && uv run python validate.py && uv run pytest` before the platform suites.

Swift tests find this folder via `FixtureLocator` (`ios/ToriKit/Tests/ToriTestSupport`), overridable with `TORI_FIXTURES`.
