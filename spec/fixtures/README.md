# Parity fixtures

Language-neutral JSON cases that pin every behaviour iOS, Android and the backend must share.
**Fixtures are normative:** if a doc and a fixture disagree, the fixture wins and the doc is fixed.

## Layout

| Folder | Files | What it pins |
|---|---|---|
| `normalization/` | `match-key`, `translation-key`, `sentence-key`, `tag-key`, `search-fold`, `url-key`, `source-key`, `text-order` | Text keys, BINARY text order and prefix ranges |
| `ids/` | `uuid-v5`, `uuid-v7`, `byte-order` | Deterministic IDs and their names, UUIDv7 layout, unsigned byte order |
| `hlc/` | `local-write`, `receive`, `clock-ahead` | HLC local write, receive (> 24 h not adopted), server 1 h skew, clock-ahead recovery |
| `merge/` | `field-comparator`, `envelope` | Comparator and envelope merge incl. partial push |
| `capture/` | `clean`, `extract`, `typed-highlight` | Capture text rules |
| `scheduler/` | `fsrs-step`, `fsrs-replay`, `day-boundary`, `queue-*`, `snapshot` | FSRS-6, replay, 04:00 day, daily queue, widget snapshot. **Generated**, see below |
| `sync/` | `001–034` | Multi-device scenarios: merge, purge, accounts, clock skew. See [Sync scenarios](#sync-scenarios) |
| `schema/` | `<kind>.schema.json` | JSON Schema 2020-12, one per fixture kind |
| `known-deviations.json` | | Must be `[]` before release; no per-platform skips |

## Case format

Every file is an object `{ "kind", "source", …file-level inputs…, "cases": [...] }`.
`kind` selects the schema (`schema/<kind>.schema.json`); `source` cites the doc sections.
Every case has a stable `id` (never renumber or reuse), its inputs, an `expected` value and an optional `note`.
Runners run one test argument per case id and print it in the test name.

- Time is always explicit (`now`, `reviewedAt`, `utcOffsetMin`); tests never read the clock or time zone.
- Instants are Unix ms (UTC), offsets minutes east of UTC, days are day numbers (days start at 04:00 local time).
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

## Sync scenarios

Kind `sync-scenario`, one case per file. A case starts at `start` (Unix ms). It names its `devices`, each with a fresh
store, and runs `steps` in order. Each step has `t` (seconds after start, strictly increasing), which is also the clock
of the device that runs it. Devices talk to one in-memory hub that implements the server envelope merge, the `seq` cursor and the
merge-group purge. Words and records are named by **aliases** (`as` on `capture`, `entry` on other ops), never by IDs.

Ops: `capture`, `editField` (`text|note|ipa|translation`), `enrich` (an automatic `translation`/`ipa`), `review`,
`exclude`, `resume`, `delete`, `tag`, `untag`, `mergeByEdit`, `setSettings`, `signIn` (optional page `limit`),
`accountChoice` (`add|remove|cancel`), `signOut`, `deleteAccount`, `sync`, `pullOnly`, `pushOnly`, `network`
(`online`), `setClock` (`offsetSec`) and `upgradeSchema`. `upgradeSchema` has no device: it writes records of a newer app
version (`schema`, unknown fields or types) straight into the hub.

`expected` describes the final logical state:

- `devices.<name>.words`: the exact set of live words. Only the listed keys of each word are compared.
- `devices.<name>.settings`, `account` (`state`, `signedIn`, `lastSynced`, `pendingChoice`, `outbox` rows) and
  `notices` (in order).
- `hub.<account>`: Entry counts (`live`, `deleted`, `merged`), `purged` aliases and per-type record counts.
- `converged`: these devices hold identical synced and derived rows. Device-local columns and hidden children of
  deleted words are left out.

| Id | Scenario |
|---|---|
| `001` | First sign-in uploads local words to an empty account |
| `002` | A new device signs in and gets everything by a full pull |
| `003` | The same field edited offline on two devices: the later edit wins |
| `004` | A user value beats a later automatic value of the same field (rank first) |
| `005` | Edits of different fields on two devices are both kept |
| `006` | The same word captured on two devices merges into one, nothing asked |
| `007` | Duplicate words with the same translation keep one Sense |
| `008` | Answers given on two devices to duplicate words are all kept |
| `009` | A delete on one device beats an offline edit on another |
| `010` | A delete beats an offline review; the late ReviewLog is dropped |
| `011` | Deleting a word that was merged elsewhere deletes the merged word |
| `012` | Children pulled before their Entry (page size 1) resolve when the parent arrives |
| `013` | The same tag created on two devices becomes one tag |
| `014` | Untag after two tags merged clears every EntryTag of the pair |
| `015` | Untag of one EntryTag does not remove a concurrent tag merged into the same pair |
| `016` | Answers to the same Card on two devices are replayed in time order |
| `017` | New scheduler settings from another device rebuild the Cards |
| `018` | Signing in to another account with no live words removes silently |
| `019` | Automatic fills on two devices write one Sense; the later wins |
| `020` | A user-edited translation survives a later automatic fill |
| `021` | Answering on another device clears 'Check translation' everywhere |
| `022` | Signing back in to the last-synced account asks nothing |
| `023` | Exclude, resume and a note on different devices all arrive |
| `024` | A confirmed merge by edit reaches the other device |
| `025` | An edit of a merged loser made elsewhere reaches the survivor |
| `026` | A push with clocks > 1 h ahead is rejected; the rows stay pending |
| `027` | After the device clock is fixed, the clock-ahead check re-stamps and pushes |
| `028` | Fields from a newer app version survive an old client's edits |
| `029` | A record type from a newer app is skipped on pull and kept on the server |
| `030` | Another account's words: Cancel pauses sync, nothing is uploaded |
| `031` | A merges X into Y while B deletes X: the whole group is purged on the server |
| `032` | Another account's words: 'Add' uploads them and merges with the account |
| `033` | Another account's words: 'Remove' needs the network, then replaces local data |
| `034` | First sign-in with local words into an account with words shows the merge summary |

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
- FSRS-6 defaults and formulas are checked against the pinned py-fsrs release (`tools/fixtures/pyproject.toml`).
- CI: `cd tools/fixtures && uv run python validate.py && uv run pytest` before the platform suites.

Swift tests find this folder via `FixtureLocator` (`ios/ToriKit/Tests/ToriTestSupport`), overridable with `TORI_FIXTURES`.
