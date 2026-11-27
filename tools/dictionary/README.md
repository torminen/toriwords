# tools/dictionary — Wiktionary → `dictionary.sqlite`

Builds the offline English→Russian dictionary bundled in the apps. Dev tool, not app code.

## Sources

| Input | Where | Licence |
|---|---|---|
| English Wiktionary, English entries | kaikki.org wiktextract JSONL (`dictionary/English/words/…jsonl.gz`) | CC BY-SA 4.0 |
| Russian Wiktionary, English entries with Russian definitions | kaikki.org ruwiktionary extraction (`ruwiktionary/Английский/…jsonl.gz`) | CC BY-SA 4.0 |
| Word frequency ranks | `wordfreq` (pinned in `pyproject.toml`) | data CC BY-SA 4.0 |

The exact inputs (URL, size, SHA-256, dump date, extraction date, wiktextract commits) are pinned in `sources.json`.
Downloads are cached in `cache/` (gitignored).

## Licence obligations (CC BY-SA 4.0)

The database is an **adaptation** of Wiktionary content, so it is distributed under CC BY-SA 4.0
(root `LICENSE-DATA`). Whoever ships it must:

- give credit: Wiktionary contributors (en/ru.wiktionary.org), wiktextract/kaikki.org, wordfreq; link the licence;
- say it was modified (filtered, merged, normalised) — `meta.licence_text` holds the wording;
- publish it share-alike: every release asset is public on GitHub Releases together with this script.

In the app: Settings → About attribution, the "Wiktionary" mark on Wiktionary-provenance values,
attribution in exports.

## Build

```sh
cd tools/dictionary
uv sync
uv run python -m toridict build      # fetches pinned inputs if missing, verifies SHA-256, builds
uv run pytest                        # unit tests; the < 10 ms autocomplete test runs when dictionary.sqlite exists
```

Outputs:

- `dictionary.sqlite` (gitignored, ≤ 60 MiB; prune ladder applied automatically if over budget, see below),
- `dictionary.sqlite.sha256`, `release.json`, `build-report.md` (counts, size, coverage, inputs, versions) — committed,
- `ios/Resources/dictionary-sample.sqlite` — a few hundred headwords of the same build, same schema,
  `dictionary_version = <ver>-sample`; committed so Debug/CI builds and tests work without the full file.

Same inputs + same tool versions (Python, SQLite, wordfreq) give the same bytes. Run the build twice and compare
`sha256sum dictionary.sqlite` before publishing.

New release (at most monthly): pick the version, re-pin the current kaikki dumps, build:

```sh
uv run python -m toridict pin --version 2026.12.1   # rewrites sources.json
uv run python -m toridict build
```

## Publish (owner)

```sh
cd tools/dictionary
gh release create dictionary-<ver> dictionary.sqlite dictionary.sqlite.sha256 build-report.md \
  --title "Dictionary <ver>" --notes "CC BY-SA 4.0, see LICENSE-DATA"
```

Then commit `sources.json`, `dictionary.sqlite.sha256`, `release.json`, `build-report.md` and the sample.

## Fetch (developers, Release builds)

```sh
tools/dictionary/fetch.sh
```

Downloads `release.json.asset_url` to `ios/Resources/dictionary.sqlite` and checks it against the committed
`dictionary.sqlite.sha256`; on mismatch the file is deleted and the script fails.

## Coverage list

`coverage/owner.txt` is used when present, otherwise `coverage/placeholder.txt` (frequent words + common phrasal
verbs/idioms, **not** the owner's content). Format: UTF-8, one word or phrase per line, `#` starts a comment, blank
lines ignored; an item whose match key contains a space counts as a phrase. Covered = exact headword key, or a form
key leading to a base headword, with ≥ 1 Russian translation. Target ≥ 90 % words, ≥ 60 % phrases.

## Build rules (as implemented)

- enwikt: English lemma senses only; `form_of`/`alt_of` senses become `form` rows of the base headword (same POS);
  obsolete/archaic/rare senses dropped when other senses exist; proper names (`name`) kept only with an RU
  translation; only `type: example` examples (≤ 3 per sense, ≤ 200 chars); Russian translations only.
  Top-level translations are tied to a sense by the first maximum of wiktextract's `_dis1` scores (else headword-level).
- One headword per (text, POS); entries for different etymologies are merged in source order.
- ruwikt: the last gloss of each sense is split on `;` into variants; leading labels (`экон.`) dropped; parts
  containing Latin letters (cross-references such as "то же, что …") dropped. Joined to enwikt by `(key, pos)` via
  the POS table in `toridict/parse.py` (`phrase` may match an enwikt verb/noun/…; `unknown` matches any);
  unmatched ruwikt entries become headwords of their own (headword-level translations, no senses).
- Text: NFC, quotes/dashes/spaces to ASCII, default-ignorables and wiki markup removed, Russian stress marks removed.
  `key` = match key (tested against `fixtures/normalization/`), `text_folded` = search fold.
- `translation_ru.rank` per headword: sense ordinal (headword-level last), then enwikt (table order) before ruwikt
  (first sense first); duplicates by translation key removed (first kept).
- `freq_rank` = 1 + number of wordfreq `large` entries more frequent than the key, only when the key itself is a
  wordfreq entry; NULL otherwise (all multi-word phrases: wordfreq's combined estimate is roughly the rarest token's
  frequency, which ranked compounds like "perfect all-kill" at ~1,500).
- `form` rows: one per (form key, headword) with the first-seen tags (head forms before conjugation tables);
  archaic/obsolete/nonstandard forms dropped.
- ruwikt variants longer than 100 characters are dropped (encyclopedic definitions, not translations); `;` splits
  only outside parentheses.
- Size budget 60 MiB. Prune ladder: base (`examples` → `related` → `rare-untranslated`: drop headwords without an RU
  translation and `freq_rank` > 100,000 or NULL), then — our extension, because the base ladder ends at ~64 MiB —
  the same rule with thresholds 50k → 20k → 10k. The first step that fits is used and recorded in `meta.prune`.
  The ladder is cumulative: once headwords are pruned, examples and related are already gone.
- IDs in (key, pos, text) order; rows inserted in key/id order; `encoding = 'UTF-8'` asserted; `page_size = 4096`; `VACUUM`.
