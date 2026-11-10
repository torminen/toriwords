# Dictionary data (Wiktionary pipeline)

Status: **Proposed**. Pending owner confirmation in step 5. Nothing here is a `decision` yet.

The offline dictionary behind autocomplete, translation variants, definitions, IPA and inflection lookup. It is the **primary** enrichment source ([enrichment.md](enrichment.md)) and is **byte-identical on iOS and Android**, so dictionary suggestions are the same on both platforms (analysis §8.7 option c).

Constraints: free and redistributable ([open source](memory://12)); judged by Russian quality ([RU → EN](memory://11)); works offline from first launch ([local-first](memory://8)).

## 1. Sources

| Source | What it gives for RU → EN | Licence |
|---|---|---|
| **English Wiktionary**, English-language entries, via **kaikki.org / wiktextract** JSONL | Headwords incl. phrasal verbs and idioms; part of speech; English glosses (definitions); IPA; inflected forms ("form of" entries: *took* → *take*); synonyms / related / derived terms; usage examples; **translation tables with Russian translations per sense** | CC BY-SA 4.0 (and GFDL) for Wiktionary text; wiktextract code MIT |
| **Russian Wiktionary** (ru.wiktionary.org), English-language entries, via kaikki.org `ruwiktionary` extraction | English words with **definitions written in Russian** — often more natural RU translations than enwiktionary translation tables, and covers senses those tables lack | CC BY-SA 4.0 |
| Word frequency list, for ranking autocomplete and senses | e.g. `wordfreq` data (CC BY-SA 4.0) or a frequency count derived from Wiktionary/Wikipedia; final choice at build time | must be CC BY-SA-compatible |

Not used in v1: Tatoeba sentences (CC BY 2.0 FR, product question I5/Q2), Wiktionary audio (per-file Commons licences; device TTS instead, [enrichment.md](enrichment.md)), paid APIs.

**Quality is `nv`.** RU coverage of both sources for the owner's vocabulary (series and articles) must be measured before the owner confirms. Proposed acceptance check in the build: for a test list of ~500 words and ~200 phrases taken from the owner's real content, report the share with ≥ 1 Russian translation. Target ≥ 90 % of words and ≥ 60 % of phrases; the rest falls back to on-device MT.

## 2. Output: `dictionary.sqlite`

SQLite 3, FTS5, read-only, opened `immutable=1`. Schema (normative once confirmed):

| Table | Columns | Purpose |
|---|---|---|
| `meta` | `key`, `value` | `dictionary_version` (e.g. `2026.11.1`), source dump dates, wiktextract version, licence text, build hash. |
| `headword` | `id`, `text` (display), `key` (match key, same normalisation as Entry match key), `pos`, `freq_rank` (NULL if unknown), `ipa`, `is_phrase` | One row per (word, POS). Index on `key`. |
| `sense` | `id`, `headword_id`, `ordinal` (stable within a build), `gloss_en`, `tags` (e.g. `informal`, `UK`) | English definitions. |
| `translation_ru` | `id`, `headword_id`, `sense_id` NULL, `text`, `origin` (`enwikt`/`ruwikt`), `rank` | Russian variants; `sense_id` set when the source ties them to a sense. |
| `form` | `form_key`, `headword_id`, `form_tags` | Inflected form → lemma (*ran* → *run*, *mortgages* → *mortgage*). |
| `example` | `sense_id`, `text_en` | Wiktionary usage examples, short ones only. |
| `related` | `headword_id`, `related_headword_id`, `kind` (`synonym`/`related`/`derived`/`phrase`) | Input for related-word suggestions (PD-6). `phrase` rows are computed at build time: dictionary phrases whose words include the headword's key or one of its forms ("mortgage" → "mortgage rate"). Lists are ranked by kind, then `freq_rank`, so both platforms show the same top 8. |
| `ru_fts` | FTS5 over `translation_ru.text` | Reverse lookup: user types Russian, gets English candidates. |

Autocomplete uses a prefix range scan on `headword.key` (`key >= ? AND key < ?||x'FFFF'`), ordered by `freq_rank`, not FTS. That is fast and works identically on both platforms.

## 3. Filtering and size budget

Build steps (each deterministic):
1. **Select** entries with `lang_code = en` from both extractions.
2. **Drop** entries with no senses; senses tagged only as obsolete/archaic/rare when the headword has other senses; proper names unless they have a Russian translation; etymology, full inflection tables, pronunciation audio, non-Russian translations.
3. **Normalise** text: Unicode NFC; apostrophes, quotes and dashes to ASCII; strip wiki markup leftovers. Compute `key` with the shared match-key normaliser spec ([parity-testing.md](parity-testing.md)).
4. **Join** ruwiktionary Russian definitions to enwiktionary headwords by `(key, pos)`. Unmatched ruwiktionary entries become their own headwords.
5. **Rank** headwords and translation variants: frequency rank; enwiktionary translation order; ruwiktionary first-sense first. Deduplicate RU variants case-insensitively.
6. **Write** the database in a fixed order (sorted by key, then id), `VACUUM`, fixed `page_size = 4096`. Same inputs → same bytes; publish the SHA-256.

**Size budget:** ≤ 60 MB uncompressed, ≤ 25 MB compressed in the app package. Expected roughly 150–300k English headwords before pruning; size after pruning is `nv` and must be measured in the first build. If the budget is exceeded, prune in this order: examples → `related` → headwords with no Russian translation and `freq_rank` beyond 100 000.

## 4. Delivery

| Option | For | Against |
|---|---|---|
| **(a) Bundled in the app** (iOS app bundle resource; Android `assets/`, or an install-time Play Asset Delivery pack if the base module gets too big) | Works offline from first launch, without an account or network, matching "fully usable locally". One code path. Same file on both platforms. Updates with each app release. | App size +~25 MB. Updates only with app releases. |
| (b) Download on first launch from own backend / CDN | Smaller app; independent updates. | First launch needs network; a server to run even for users without an account; failure modes on first launch. |
| (c) Bundled baseline + optional versioned updates from backend | Best of both. | Two code paths; update logic and integrity checks. |

**Recommendation: (a) for v1**, (c) later if dictionary updates between app releases turn out to matter. On first launch the app copies (iOS: into the App Group container, so the share extension can read it) or opens it in place (Android assets must be copied to files to open with SQLite), excluded from backups. When a new app version ships a new `dictionary_version`, the old file is replaced atomically.

**Cadence:** rebuild for each feature release, at most monthly, from the latest kaikki dumps. The build log records the dump dates.

## 5. Licence: CC BY-SA 4.0 obligations

- **The database file is an adaptation of Wiktionary** and is distributed under **CC BY-SA 4.0**. The app's source code licence is separate; the database is a separate data file shipped alongside, not merged with code.
- **Attribution:** in the app's About / Licences screen and in the repository (`tools/dictionary/README` and a `LICENSE-DATA` file): "Dictionary data from Wiktionary (en.wiktionary.org, ru.wiktionary.org), contributors, CC BY-SA 4.0, extracted with wiktextract (kaikki.org); modified (filtered, merged, normalised)", with links to the sources and the licence.
- **Share-alike:** the built database and the build script are published (release asset + repo), so anyone can get and re-create the adapted data under the same licence.
- **User data copied from the dictionary** (a chosen translation or definition) keeps provenance on the Sense ([domain-model.md](../product/domain-model.md), *Enrichment*), so the app can show "from Wiktionary" next to it. If the product adds export, exported Wiktionary-derived text carries the same attribution line.
- Frequency data must be CC BY-SA 4.0 or more permissive (CC BY / CC0 / public domain).

## 6. Build script (specified, not written)

- Location: `tools/dictionary/` in the repository. Language: Python (the wiktextract ecosystem is Python). It is a dev tool, not app code, so it doesn't conflict with "no shared code" ([memory://7](memory://7)).
- Inputs: pinned URLs and SHA-256 of the kaikki JSONL dumps (English entries from enwiktionary; ruwiktionary extraction), frequency list, the normaliser spec fixtures.
- Steps: download and verify → stream-parse JSONL (multi-GB; never load whole) → §3 steps → write SQLite → run the coverage check (§1) and the normaliser fixtures → print size and stats → write `meta`.
- Outputs: `dictionary.sqlite`, `dictionary.sqlite.sha256`, `build-report.md` (coverage, size, counts).
- Run by: a developer locally or a manual CI job before a release. Not part of the app builds; the apps consume the published file.

## 7. Open questions

- **Q-D1 (owner):** is the measured RU coverage (§1 check) good enough to make Wiktionary the primary source, with on-device MT as fallback? Decided after the first build.
- **Q-D2 (owner):** accept ~25 MB extra app size for an offline dictionary from first launch? Recommendation: yes.
- **Q-D3 (product):** reverse RU → EN lookup ("how do I say …") and related-word suggestions from `related` are available from the same file at no extra cost. Adopt in v1?
