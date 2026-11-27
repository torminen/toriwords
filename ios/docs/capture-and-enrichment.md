# Capture, dictionary, enrichment and pronunciation

How words get into ToriWords on iOS and how they are filled in:
- the Share Extension capture sheet, its inbox and the vocabulary index;
- the shared capture text rules;
- the bundled dictionary;
- on-device machine translation (Apple Translation);
- pronunciation (text-to-speech).

Related files:
- [data-model.md](data-model.md): tables, columns and provenance fields.
- [architecture.md](architecture.md): targets, modules, start-up, App Group files.
- [scheduler.md](scheduler.md): when a word becomes reviewable.
- [sync.md](sync.md): ranks, clocks and the outbox stamped by every write here.
- [ui.md](ui.md) and [copy.md](copy.md): screens and wording.

**Fixtures win.** These are normative:
- `fixtures/capture/`: `clean`, `extract`, `typed-highlight`;
- `fixtures/normalization/`: match, translation, sentence, tag and search keys, URL and source keys, text order.

The exact character lists (quotes, dashes, spaces, ignorables, closers, speaker labels, annotations, what counts as a Latin letter) are in `fixtures/README.md` under "Rules for the text functions". They are not repeated here.

## Capture surfaces

| Surface | Mechanism |
|---|---|
| Selected text in any app | Select text → **Share** → ToriWords (the Share Extension `ToriwordsShare`). |
| Shared text or link | Share sheet → ToriWords, from any app that shares plain text, one web URL or one web page. |
| A Safari page | Share from Safari runs the JavaScript preprocessing: the selection, the page title, the URL and the sentence around the selection. |
| In-app typing | The Add screen in the main app. |
| Deep link | `toriwords://add?text=…` opens Add with the text ([architecture.md](architecture.md#deep-links)). |

Not in v1:
- screenshot OCR;
- Shortcuts / App Intents actions;
- capture from streaming-app subtitles. Text works only where the source app allows selection or sharing.

**Share-menu tip.** The first time the capture sheet opens, it shows "Tip: put ToriWords first" with the steps to move ToriWords to the front of the share row. The `tipShown` flag in `capture-sticky.json` keeps it from showing again.

## Share Extension

**Activation rule** (`Info.plist`, `NSExtensionActivationRule`):
- `NSExtensionActivationSupportsText = YES`;
- `NSExtensionActivationSupportsWebURLWithMaxCount = 1`;
- `NSExtensionActivationSupportsWebPageWithMaxCount = 1`.

In the Personal configuration the rule is `FALSEPREDICATE`, so the extension never appears ([architecture.md](architecture.md#personal-configuration)).

**Process:**
- The extension is a **separate process**. It never opens `user.sqlite`, uses no network and no Keychain.
- It reads the dictionary from the containing app's bundle, the vocabulary index and the sticky fields from the App Group, and saves by writing **one inbox file** into the App Group. The app imports the file into the database ([Inbox and import](#inbox-and-import)).
- The principal class is `ShareViewController` (UIKit). It reads the shared items, builds a `SharePayload`, then hosts the SwiftUI `ShareSheetView` over a `ShareModel` (`@MainActor @Observable`).
- Save completes the extension request (`completeRequest`) after a short "Saved" (700 ms); Cancel cancels it (`cancelRequest` with `userCancelled`). Both return to the source app.

**Keeping it light:**
- The extension runs no sync, no replay, no enrichment and no index rebuild.
- Follow-up work (enrichment fill, widget snapshot, sync) runs in the app after import.

### JavaScript preprocessing (Safari)

`ShareExtension/ExtensionPreprocessing.js` runs in the Safari page and returns a dictionary with four strings:
- `selection`: `String(window.getSelection())`;
- `title`: `document.title`;
- `url`: `document.URL`;
- `sentence`: the sentence around the selection, or empty.

**Sentence around the selection:**
1. From the selection's start node, walk up to the nearest block element: `P`, `LI`, `TD`, `TH`, `DD`, `DT`, `DIV`, `BLOCKQUOTE`, `H1`–`H6`, `ARTICLE`, `SECTION`, `FIGCAPTION`, `PRE` or `BODY`.
2. In that block's `textContent`, sentence ends are `.`, `!`, `?` or `…`, optionally followed by closing quotes or brackets (`" ' ” ’ » ) ]`), then whitespace.
3. The sentence runs from the last end before the selection to the first end after it.
4. Whitespace is collapsed and trimmed. A result longer than 2,000 characters is dropped.

The presence of this result is what marks a share as **from Safari**. Other browsers and apps do not run it.

### Shared items

`ShareViewController` reads every `NSExtensionItem`:
- `attributedContentText`, as plain text;
- attachments: the preprocessing property list, else a URL item, else a plain-text item (in that order per provider).

`SharePayload(javaScript:texts:urls:)` then decides (`ToriShared/ShareCapture.swift`):
1. **URL** = the preprocessing `url`, else the first URL item. Values are trimmed; empty values count as missing.
2. **Text** = the preprocessing `selection`. Without one, the first text item that is not itself a web URL. A text item that is only an `http://` or `https://` URL with no whitespace counts as the URL (if none was found yet).
3. If the text equals the URL, the text is dropped.
4. **Title** = the preprocessing `title`. **Sentence** = the preprocessing `sentence`.
5. **Remaining text is empty:** this is a **link-only share**. The sheet has nothing to save until the user types the word in the text field.
6. **Otherwise:** the text goes through the capture text rules below.

For a **term** source from Safari, the sheet attaches the Safari sentence: it looks for the chip span whose match key equals the term's and extracts that sentence and highlight (rule 4). If the term is not found, the cleaned sentence is kept whole with a typed-sentence highlight (rule 6), unless it is longer than 500 code points, in which case it is dropped.

### Source

**What is stored** (inbox `source`):
- `url`: the shared URL, if any.
- `title`: the Source title field (pre-filled from the shared title, else the sticky title), if not blank.
- `app`: `"Safari"` only when the share came from Safari, else absent. iOS does not tell an extension which app shared, so no other app names are stored.
- No `source` at all when there is neither a URL nor a title.

**What is shown:** "Safari · theguardian.com" when the share came from Safari; the domain alone (host without a leading `www.`) for other shares with a URL; nothing without a URL.

**Source kind** (at import, `CaptureInput(_ file:)`):

| Situation | Kind | ID |
|---|---|---|
| URL present | `web` | deterministic, `v5("source:"+urlKey)` |
| Title only | `other` | UUIDv7 |
| Neither title nor URL | no Source | — |

The kind `app` is never created by the Share Extension. Sources without a URL merge by `matchKey(title)` + the stored app name + kind ([sync.md](sync.md#natural-keys)).

## Capture text rules

The same rules apply to every text entry point: the capture sheet and the Add field. They are implemented once, in `ToriCore/Capture.swift`. Lengths and cuts count Unicode code points; highlight offsets and lengths are UTF-16 code units.

### 1. Clean

1. Remove `<…>` tags.
2. Remove `[…]` and `(…)` annotations that contain only letters and spaces (subtitle markup such as `[music]`).
3. Remove a leading speaker label: up to 3 words followed by `:` at the start of a line.
4. Turn line breaks into spaces, remembering them as sentence boundaries, and collapse whitespace.
5. Keep only the first **5,000** characters (Unicode code points).

### 2. Classify

The text is a **sentence source** if either:
- it has **more than 6 words** (whitespace-separated tokens after cleaning); or
- it ends with `.`, `!`, `?` or `…`, optionally followed by closing quotes or brackets.

Otherwise it is a **term**. A sentence source is shown as tappable word chips ("Tap the word to save"): the user taps one word, or several adjacent words, to choose the term.

**Chip taps** (`CaptureDraft.tapChip`): tapping a chip next to the picked span extends it; tapping a picked end chip shrinks it; tapping the single picked chip unpicks it; tapping any other chip starts a new pick. Chips are the whitespace tokens of the cleaned text with leading and trailing punctuation stripped.

### 3. Reject

Text without any Latin letter cannot be saved. Save is disabled ("ToriWords saves English words and phrases"), and the user can edit the text.

### 4. Sentence extraction

For sentence sources only. Keep the one sentence that contains the chosen span.
- **Boundaries:** `.`, `!`, `?` or `…`, optionally followed by closing quotes or brackets, then whitespace. A line break in the original text also counts.
- **Longer than 500 characters:** cut to 500 around the chosen span, at word boundaries, and mark the cuts with `…`. The cut grows one word to the left, then one to the right, while the result still fits.
- **Highlight:** the chosen span becomes the highlight, as an offset and length in **UTF-16 code units** within the stored sentence (what `NSRange` uses).

### 5. Entry text

- Term sources: the whole cleaned text.
- Sentence sources: the chosen span.

### 6. Highlight for typed sentences

A sentence typed or edited on the Add screen, in the capture sheet or in the Entry edit form has no chosen span.
- On save, the highlight is the **first** occurrence of the Entry text in the sentence, compared with match-key folding (case, typographic quotes, apostrophes, dashes) at word boundaries. "First" means the smallest start, then the smallest end.
- Not found means no highlight. The Context then gets no cloze card, and the recall front does not use it.
- It is recomputed when either text is edited, unless the user moved it.

### Dictionary offers for the chosen term

These are the same on the Add screen and in the capture sheet.

**Base form.** A single inflected word with no headword of its own, but a `form` hit:
- The sheet offers "Save as" with the base form (preselected) and the captured form.
- Phrases are never changed.

**Contained-phrase chips.** A multi-word term, or a typed sentence on the Add screen:
- Dictionary phrases (2–6 words) found inside it, also through the base forms of its words, are offered as opt-in chips ("Phrases"). For example, "looked after" offers "look after".
- Tapping a chip makes that phrase the saved Entry text; tapping it again goes back.
- The algorithm (`BundledDictionary.containedPhrases`):
  1. Tokenise the text's match key (at most 64 tokens).
  2. For each start position, from the longest span (at most 6 words) down to 2, build variants: the words as typed, then with words replaced by their base forms from `form` (non-phrase headwords only). Stop at 16 variants per span.
  3. Keep the variants that are phrase headwords (`is_phrase = 1`), excluding the text's own key.
  4. Order by first position in the text, then longer first.
  5. Show at most 8.

In both cases the **sentence keeps the captured text**: the highlight stays on the span as captured. Offers whose match key equals the captured text are dropped.

## Capture sheet contents and save

### What the sheet shows

**Senses and variants:**
- Dictionary senses and Russian variants for the saved text, from the bundled dictionary (`Variant.of(headwords)`), with the IPA of the first headword that has one.
- The first variant is preselected.
- The user can multi-select variants. Only when there are **no** variants, a "Translation (optional)" field is shown ("Not in the dictionary"); its value is saved as a `user` Sense.
- Without any translation the word is saved as "Translation pending".

**Machine translation:** none in the capture sheet. Apple Translation runs only in the app.

**Duplicate check:**
- A lookup of the term's match key in `vocab-index.json` (the sheet cannot read the database).
- If found: "Already in your vocabulary" with up to 3 translations, and "Save adds this sentence and source."
- If its status is `known` ("You marked this as known") or `paused` ("You paused this word"), the sheet offers a **Resume learning** toggle.
- The index can be stale (written by the app after changes, debounced). The import repeats the duplicate check against the database inside its transaction, so a stale index cannot create a duplicate.

**Tags:** comma-separated names, trimmed, first spelling kept per tag key. Suggestions are the sticky tags first, then the tag names from the vocabulary index, without repeats by key.

**Source title:** pre-filled from the shared title, else the sticky title.

### Save

**In the Share Extension** (`ShareModel.save()`):
1. **No App Group** (`AppGroup.shared` is nil) → the alert "Could not save. Open ToriWords once, then try again."
2. Build the inbox file from the draft: the Entry text, the sentence and highlight, the Source, the tags, the picked variants (each with `wiktionary` provenance: `dictVersion`, `headwordKey`, `senseOrdinal`), the typed translation, `origin = shared`, `resume`, `captureId` = a new UUIDv7, `capturedAt` = now, `utcOffsetMin` = the current offset.
3. Write it atomically to `inbox/<captureId>.json`. **A write failure** → the same alert.
4. Update the sticky fields.
5. Post the Darwin notification `com.toriwords.inbox.changed`.
6. Show "Saved", then complete the request after 700 ms.

**In the app** the inbox file becomes one call to the **capture use case** (`ToriStore.capture`, `ToriStore/CaptureUseCase.swift`). It is the same use case the Add screen uses, and it runs as one transaction:
1. **Entry:** find the live canonical Entry with the term's match key in the language pair, or create it.
   - `origin`: `shared` (Share Extension) or `typed` (Add).
   - `created_at` = the capture time.
   - A new Entry gets `needs_check = 0` and `enrichment_status = pending` (rank 0).
2. **Senses:** add the picked or typed ones (rank 1, with provenance), skipping translation keys the Entry already has.
3. **Context:** add the sentence with its highlight, or a source-only Context, unless one with the same sentence key and canonical Source exists.
4. **Source and Tags:** add or reuse them.
5. **Resume learning**, if chosen and the Entry is excluded: `status = active`, `excluded_reason = NULL`, rank 1.
6. **Enrichment status:** set `enrichment_status = pending` (rank 0) when the Entry has no live Sense with a translation.
7. **Clocks:** stamp clocks and outbox rows.

### After commit

In the app, after an import or an Add:
1. If anything was imported, or an Add saved no meaning, run pending enrichment (`EnrichmentOrchestrator.runPending`).
2. Rewrite the App Group files (vocabulary index and widget snapshot, debounced 2 s) and reload the widget timelines.
3. Refresh the reminders.
4. The sync coordinator sees the outbox grow and syncs after 5 s.

### Sticky capture fields

- Kept in the App Group file `capture-sticky.json`: `format` (1), `updatedAt` (ms), `sourceTitle` (nullable), `tags` (names), `tipShown`.
- The title and tags are offered again for **30 minutes** after `updatedAt`. After that the sheet starts empty, except for a shared title. `tipShown` never expires.
- Written only by the Share Extension on Save (and when the tip is shown), and read only by the Share Extension. The Add screen does not pre-fill from them.
- Not synced.

## Inbox and import

### Inbox file (format 1)

One JSON file per pending capture, `inbox/<captureId>.json` in the App Group, written atomically (`inbox/.tmp-<captureId>.json`, then rename). Keys are sorted.

| Field | Type | Meaning |
|---|---|---|
| `format` | int | `1` |
| `captureId` | UUIDv7 string | Identity of the capture; also the import idempotency key |
| `capturedAt` | int (ms) | Capture time; becomes `created_at` and `captured_at` |
| `utcOffsetMin` | int | Offset at capture time |
| `languagePair` | `{ "native": "ru", "target": "en" }` | Language pair |
| `term` | string | The Entry text (after a "Save as" choice) |
| `sentence` | string, optional | Context sentence |
| `highlight` | `{ "offset", "length" }`, optional | UTF-16 code units in `sentence`; only with a sentence |
| `source` | `{ "url"?, "title"?, "app"? }`, optional | See [Source](#source) |
| `tags` | [string], optional | Tag names |
| `chosenSenses` | [`{ "translation"?, "definition"?, "pos"?, "provenance": { "kind", "dictVersion"?, "headwordKey"?, "senseOrdinal"? } }`] | Picked variants; `kind` is `wiktionary` or `user`. Missing = `[]` |
| `typedTranslation` | string, optional | Becomes a `user` Sense |
| `origin` | string | `shared`; missing = `shared` |
| `resume` | bool | The user chose Resume learning; missing = false |

### Import

`ToriStore.importInbox` runs:
- at launch, on becoming active, on the Darwin notification while the app runs, and in the background refresh ([architecture.md](architecture.md#7-start-up-first-run-restore-and-reinstall));
- over the pending IDs in UUIDv7 byte order (files named `<uuid>.json`; temp files and other names are ignored);
- **one transaction per file**: the capture use case plus a row in the local `inbox_import` table (`inbox_id`, `imported_at`). The file is deleted after the commit.
- **Idempotent:** a file whose ID is already in `inbox_import` is deleted without importing it again (a crash between commit and delete).
- **Unknown `format`** or an unreadable file: left in place untouched, for a later app version.

## Vocabulary index

`vocab-index.json` in the App Group gives the Share Extension its duplicate hints and tag suggestions. It is written by the app (`ToriStore.writeAppGroupFiles`) together with the widget snapshot: at launch, 2 s after any vocabulary change, on entering the background and in the background refresh.

```json
{ "format": 1, "generatedAt": 1762790400000,
  "entries": [ ["look after", "0193…", ["присматривать"], "active"] ],
  "tags": [ ["travel", "Travel"] ] }
```

- `entries`: one array per live canonical Entry with a match key: `[matchKey, canonicalEntryId, translations, status]`, ordered by match key, then ID.
  - `translations`: up to 3 non-empty translations of live Senses, in display order.
  - `status`: `active`, `known` (excluded, reason known) or `paused` (excluded, reason paused).
- `tags`: `[nameKey, name]` for live Tags, ordered by name key, then ID.
- A lookup compares match keys as UTF-8 bytes.

## Editing meanings: suggestion provenance

The Entry edit form lists **suggested meanings** above "Add meaning". These are dictionary variants and the machine translation that the Entry does not have yet, compared by translation key.
- Removing a meaning offers it as a suggestion again.
- Tapping "Add meaning" from read mode adds a blank row only when there are no suggestions to offer.

**Provenance of a picked suggestion:**
- It is saved **with its original provenance**: `translation_src` (`wiktionary` or `mt_apple`), `dict_version`, `dict_headword_key`, `dict_sense_ordinal`.
- This holds only while its translation, definition **and** part of speech are all unchanged.
- If the user edits any of the three before saving, the row is saved as a plain user Sense (`user` provenance).
- The draft row keeps the original suggestion and compares all three fields at save time (`EntryDraft.Meaning.newSense`).

## Dictionary

An offline English→Russian dictionary built from Wiktionary.
- It is built by `tools/dictionary/` (see `tools/dictionary/README.md`) and published as a GitHub Release asset.
- Release builds fetch it with `tools/dictionary/fetch.sh`, which checks the committed SHA-256.
- Same inputs give the same bytes.
- Size budget: ≤ 61 MiB uncompressed.

### Delivery: read in place from the app bundle

- The file is an app resource: `Resources/dictionary.sqlite` (a build artefact, never hand-edited, not in git). **Debug builds** without it ship the committed sample `Resources/dictionary-sample.sqlite` (same schema). A Release build fails without the full file.
- `BundledDictionary.bundledURL()` finds it: from the app, in the main bundle; **from the Share Extension** (`….app/PlugIns/ToriwordsShare.appex`), in the containing app's bundle. It tries `dictionary.sqlite`, then `dictionary-sample.sqlite`.
- There is **no copy and no install step**. The file arrives with the app and is replaced only by an app update.
- **Before the first app open:** the Share Extension opens the dictionary straight from the bundle, so lookups, variants, base forms and phrases work from the first install, before the app was ever opened.
- **Version change:** at launch the app compares `meta.dictionary_version` with the version stored in `UserDefaults` (`dictionaryVersion`). A change runs `EnrichmentOrchestrator.updateDictionary`, which retries `unavailable` Entries.
- **Legacy copy:** older builds copied the file into the App Group. Launch deletes such a copy if it is still there.

### Access

- Opened by `ToriDictionary` with GRDB, **read-only** (`readonly = true`) and immutable (`file:<path>?immutable=1`). It does not go through `ToriStore`.
- The system SQLite provides FTS5.
- The app holds one `BundledDictionary` (a `DatabaseQueue`). The Share Extension opens its own per capture, lazily.
- The file is never written; the bundle is read-only.

### Schema (read-only, normative)

| Table | Columns |
|---|---|
| `meta` | `key`, `value`: `dictionary_version` (for example `2026.11.1`; `…-sample` for the sample), dump dates, wiktextract version, licence text, build hash, prune level |
| `headword` | `id`, `text`, `key` (match key), `pos`, `freq_rank` (NULL = unknown; set only for single words), `ipa`, `is_phrase`; index on `key` |
| `sense` | `id`, `headword_id`, `ordinal` (stable within a build), `gloss_en`, `tags` |
| `translation_ru` | `id`, `headword_id`, `sense_id` (NULL = not tied to a sense), `text`, `text_folded`, `origin` (`enwikt` / `ruwikt`), `rank` |
| `form` | `form_key`, `headword_id`, `form_tags` |
| `example` | `sense_id`, `text_en` |
| `related` | `headword_id`, `related_headword_id`, `kind` (`synonym` / `related` / `derived` / `phrase`); `WITHOUT ROWID`, primary key `(headword_id, related_headword_id)`; at most 8 per headword (the first 8 in the query order below), targets with ≥ 1 Russian translation |
| `ru_fts` | FTS5 over `translation_ru.text_folded` (lowercased, `ё`→`е`), tokenizer `unicode61 remove_diacritics 0` |

**Pruned builds:** a build may prune `example` and, as the last resort, `related` to fit the size budget. Build 2026.11.2 has no examples and keeps related rows. When a word has no `related` rows, the related-words section is hidden.

**No dictionary row IDs in user data:** provenance is `(dict_version, dict_headword_key, dict_sense_ordinal)` plus a copy of the text, so a new build cannot break user data.

### Queries

All text comparisons are SQLite `BINARY` on UTF-8. There is no in-memory sort by Swift `String` comparison: it orders by Unicode canonical equivalence, not by UTF-8 bytes. `x'FFFF'` closes a prefix range.

**Autocomplete** (English input, from the 2nd character), up to 8 rows in total (`Autocomplete`, `ToriEnrichment/AddDraft.swift`):
1. Live canonical user Entries whose `match_key` starts with the typed key, ordered by `match_key`, then `id`, up to 3. They are marked "In your vocabulary", and tapping one opens the Entry.
2. Then the dictionary, skipping keys already listed: `SELECT … FROM headword h WHERE h.key >= :p AND h.key < :p || x'FFFF' ORDER BY h.freq_rank IS NULL, h.freq_rank, h.key, h.id`.
3. Concatenate in that order. Target: under 10 ms.

Input is **Russian** when it has a Cyrillic letter (U+0400–U+04FF) and no ASCII Latin letter; otherwise it is English.

**Lookup:**
- `headword WHERE key = :k` (several parts of speech possible), ordered `freq_rank IS NULL, freq_rank, key, id`.
- Forms: `form WHERE form_key = :k` (base-form offer), ordered the same way.

**Reverse (Russian input):**
- Applies when the input has a Cyrillic letter (U+0400–U+04FF) and no Latin letter, and at least 2 letters.
- Search-fold it, then match `ru_fts MATCH '"<folded>"*'`.
- One row per headword, ordered by its best matching `translation_ru.rank`, then `freq_rank` (NULL last), `key`, `id`. Each row carries the Russian variant that matched.

**Suggestions per sense** (`Suggestions.build`):
- Russian variants, English gloss, part of speech.
- Ordered by headword (lookup order), then sense `ordinal`, then variant `rank`.
- Variants not tied to a sense come after the sense-tied ones.
- Variants are deduplicated by translation key.

**Related words** (`DictionarySearch.related`, `App/Shared/RelatedWords.swift`):
- Up to 8 for the word's headword, or for its base form (single words only).
- Ordered by kind (`synonym`, `related`, `derived`, `phrase`), then `freq_rank` (NULL last), then `related_headword_id`.
- One-tap Add saves the item with its rank-1 variant, that sense's gloss and dictionary provenance, and no sentence.
- It adds a source-only Context with a Source of kind `suggested` whose `title` is the origin headword (stored as text, not localised).
- Items already in the vocabulary show as such ("✓ In vocabulary").
- ✕ hides an item for the current screen visit only.

### Licence

**Settings → About** shows the short attribution row "Dictionary data from Wiktionary, CC BY-SA" ([copy.md](copy.md)), linking to the licence.

**Full attribution text:** the Licences screen and the backup file's `attribution` field carry it: "Dictionary data from Wiktionary (en.wiktionary.org, ru.wiktionary.org), contributors, CC BY-SA 4.0, extracted with wiktextract (kaikki.org); modified (filtered, merged, normalised)", with links to the sources and the licence.

**Wiktionary mark:** shown next to Sense values whose provenance is `wiktionary`.

**Exports:**
- A CSV export gets a trailing one-cell attribution row, but only when it contains Wiktionary-derived text.
- The share message carries the attribution too.

## Enrichment

### Principles

1. **Dictionary first, Apple Translation as fallback and suggestion.**
   - The dictionary gives several sense-tied variants, definitions and IPA, identical to Android.
   - Machine translation gives one variant and may differ from Android (accepted).
2. **Store what the user accepts, and never re-enrich silently.**
   - Accepted values are written to Senses with provenance and synced.
   - Enrichment fills only **empty fields whose last write had rank 0**. A rank-1 (user) field is never written by enrichment again, even if the user emptied it.
3. **No LLMs and no ToriWords server.**
   - Translation runs on the device.
   - Only Apple's language-data download uses the network.

### Pipeline (Add screen)

1. **Normalise:** compute the match key.
2. **Look up:**
   - An exact headword hit, else a form hit, which gives the base-form offer.
   - For multi-word text, contained phrases.
3. **Suggestions per sense,** in the order above.
4. **Machine translation** (`EnrichmentOrchestrator.suggestions`):
   - With no dictionary hit, Apple Translation's result is the main suggestion, labelled as machine translation.
   - With a hit, it is added as one extra variant only if its translation key differs from every dictionary variant.
   - Only when the translator is ready ([Apple Translation](#apple-translation)).
   - **Sentence help:** when a sentence is available, "In this sentence: …" shows its machine translation.
     - It runs only when the translator is ready.
     - It is debounced 600 ms.
     - It is never stored.
5. **User decision:** each picked variant becomes a Sense (rank 1). Provenance per field:
   - `wiktionary` + `dict_version` + `dict_headword_key` + `dict_sense_ordinal`; or
   - `mt_apple`; or
   - `user`.
6. **IPA** from the first headword with one is stored on a new Entry with rank 0; an edited IPA has rank 1.

The capture sheet runs steps 1–3 and 5 only (no machine translation).

### Pending Entries and retries

| Situation | Behaviour |
|---|---|
| Dictionary hit, user picks | Senses saved; the Entry has a translation. |
| Saved without a chosen translation | `enrichment_status = pending`. **Automatic fill** when the app runs: the first dictionary suggestion, or the Apple Translation result if there is no hit, goes into an automatic Sense with ID `v5("autosense:"+entryId+":0")`, rank 0, with provenance. Then `needs_check = 1` (rank 0) and `enrichment_status = done`. With a dictionary hit, the headword's IPA is stored (rank 0) if the Entry has none. The Entry is listed under **Check translation**. |
| No dictionary hit, translator not ready or offline | Stays `pending`, with no translation and no cards. Listed under **Needs translation**. Retried later; it does **not** count an attempt. |
| Apple Translation failed or returned nothing 3 times (no dictionary hit) | `enrichment_status = unavailable`: "No translation found — add your own", with **Try again**. |
| `unavailable`, and a new source appears (newer dictionary, EN→RU language data installed) | Every `unavailable` Entry goes back to `pending` with a fresh attempt count, then the fill runs. A fill writes rank 0 only, so fields the user wrote stay as they are. Success sets `done`. |
| A dictionary read error, or a headword without Russian variants | Counts as no hit, so Apple Translation gets its chance. |
| Device where Apple Translation is unsupported | No dictionary hit stays `pending` ("Translation pending"): the translator never becomes ready, and no attempt is counted. **Try again** and a dictionary update re-run the dictionary step. |
| User typed a translation, and enrichment finds more | Offered as suggested meanings on the Entry screen; never added automatically. |
| User cleared an automatic translation | The field is now rank 1 and empty, and it stays empty: "No translation yet". |

**Retry mechanics:**
- `entry.enrich_attempts` (local, never synced) counts Apple Translation failures. The third failure sets `unavailable`.
- Background retries use an in-memory backoff per Entry (1, 2, 4 … min, doubling up to 2^10 min), so foreground triggers do not use up the 3 attempts.
- **Try again** and a new source reset the backoff and the attempt count.
- A translation cancelled because the app left the foreground (iOS below 26, see below) defers the Entry and does not count a failure.

**Concurrent fills:** two devices filling the same pending Entry offline write the same automatic Sense IDs. Per-field merging keeps one value per field, so there are no duplicate Senses.

### Translation state shown in the UI

Derived, never stored. An Entry **has a translation** when it has at least one live Sense with a non-empty `translation`.

| State | Condition (first match wins) | UI |
|---|---|---|
| has translation | ≥ 1 live Sense with a non-empty translation | the primary translation |
| not found | `enrichment_status = unavailable` | Status label "No translation found"; the list's second line and the Entry screen banner say "No translation found — add your own" ([copy.md](copy.md)) |
| pending | `enrichment_status = pending` | "Translation pending" |
| none | otherwise | "No translation yet" |

- The three states without a translation show the stage **Needs translation** and appear under that filter.
- Saving with nothing picked or typed always gives `pending`.

### `needs_check`

**Set:** set to 1 (rank 0) by an automatic fill.

**Cleared** (to 0, rank 0) when either:
- the Entry screen is opened (`ToriStore.markChecked`); or
- an answer for one of its cards is committed.

**Rules:**
- It is cleared only if it is currently 1, so viewing writes nothing otherwise.
- It is never written with rank 1, so a later automatic fill on another device can raise it again.

### Enrichment work

**Background fills** run in `EnrichmentOrchestrator` (an actor). One pass walks every pending Entry (ordered by `created_at`, then ID); a trigger during a pass schedules exactly one more pass. Many pending Entries are processed in one pass.

**Triggers:**
- launch (after the store opens): `runPending`, or `updateDictionary` when the dictionary version changed;
- the app becoming active;
- an inbox import that imported something;
- an Add with nothing picked;
- the background app refresh;
- EN→RU language data becoming installed (Settings → Translation): `retryUnavailable`;
- **Try again** on one Entry: `tryAgain`.

## Apple Translation

- The Translation framework, `Locale.Language("en")` → `Locale.Language("ru")`. Runs on the device once the language data is installed.
- Provenance of its output: `mt_apple`.
- Adapter: `AppleTranslator` (`ToriEnrichment/AppleTranslator.swift`), behind the `MachineTranslator` protocol.

### Readiness

`isReady()` is true when `LanguageAvailability().status(from: en, to: ru)` is `.installed` and, **below iOS 26**, the bridge is active (the app is in the foreground). Interactive features and the background fill both check it before translating.

### Sessions

- **iOS 26 and later:** each translation creates `TranslationSession(installedSource: en, target: ru)` and calls `translate`. It needs no UI, so background fills work in the background refresh too.
- **iOS 18–25:** a `TranslationSession` is only available from the SwiftUI `.translationTask` modifier. The app keeps a hidden `.translationTask(env.translationBridge.configuration)` on its root view. `TranslationBridge` (`@MainActor`):
  - queues each request and sets (or invalidates) its configuration, which makes SwiftUI hand a session to `serve(_:)`;
  - `serve` drains the queue serially with that session;
  - while the app is not active, requests fail at once with `CancellationError`, and `cancelAll()` ends queued requests when the app enters the background. A cancelled task leaves the queue. Nothing waits forever.

  So below iOS 26, background fills without a dictionary hit wait for the next foreground.

### Language-data download

- Never automatic, and never started by Add, the Entry screen or the capture sheet.
- **Settings → Translation → Download** sets a configuration on a `.translationTask` in that screen and calls `session.prepareTranslation()`. The system shows its own download prompt; the call returns when the user has answered.
- The user can also add English and Russian in iOS Settings → Apps → Translate → Downloaded Languages. The screen re-checks the status when the app becomes active again.
- When the status changes to `.installed`, the screen calls `retryUnavailable()`.

### States

Shown in Settings → Translation, together with the dictionary version ("Bundled", "Dictionary (Wiktionary)", "Version …").

| `LanguageAvailability` status | Shown |
|---|---|
| `.installed` | "Ready" |
| `.supported` | **Download** button, and a footer explaining both download paths; "The dictionary works without it." |
| `.unsupported` | "Not available"; "Apple Translation is not available on this device. The built-in dictionary still suggests translations." |

The bundled dictionary always works. The translation state is not shown on Home.

### Disclosure

Apple Translation runs on the device and the app sends no text anywhere. No extra disclosure is needed.

## Pronunciation (TTS)

- `AVSpeechSynthesizer`, one `SpeechPlayer` instance owned by `AppEnvironment` (`@MainActor`).

### Voice choice

The accent is a per-device setting:
- US → `en-US`;
- UK → `en-GB`.

**Picking a voice** (`VoicePicker`, `SpeechPlayer.pickVoice`):
1. Take `AVSpeechSynthesisVoice.speechVoices()` with the accent's language.
2. Prefer the highest quality: premium, then enhanced, then default. Ties are broken by identifier.
3. **Default-voice rule:** if the best candidate has default quality and the accent's language, use the system voice for that language (`AVSpeechSynthesisVoice(language:)`, for example Samantha for en-US, Daniel for en-GB) instead. Among default-quality voices the identifier tie-break would otherwise pick novelty voices.
4. If no voice has the accent's language, use the best `en-*` voice.
5. No English voice at all → no usable voice.

**Caching:** the choice is cached per accent, and dropped when `AVSpeechSynthesizer.availableVoicesDidChangeNotification` arrives or the accent changes.

### No usable voice

- The speaker button stays visible but dimmed.
- Tapping it shows "No English voice" with the steps: Settings → Accessibility → Spoken Content → Voices → English.
- IPA stays visible.

### What is spoken

- **Tap** on ▶: the English word or phrase.
- **Long-press** on ▶ (where a sentence is available): the sentence. VoiceOver gets a "Play sentence" action.
- Russian is not spoken in v1.

### Audio

**Audio session**, activated on a serial queue off the main thread before each utterance:
- **Tap and long-press:** category `.playback`, mode `.spokenAudio`, option `.duckOthers`. It speaks even with the silent switch on, and other audio ducks meanwhile.
- **Auto-play on reveal:** category `.ambient`, mode `.spokenAudio`. It follows the silent switch, so a silenced phone makes no automatic sound, and it mixes with other audio.
- After an utterance finishes or is cancelled, the session is deactivated with `.notifyOthersOnDeactivation`, unless another utterance is speaking or a newer one is on its way (a generation counter).

**Auto-play on reveal:** a per-device setting, default off.

**Stopping:** speech stops when the card changes, when the screen goes away and when the app enters the background.

**Storage:** audio is generated on demand, and never stored or synced.

## Open questions

1. **Stale capture-sheet line.** With no variants and no dictionary, the sheet says "The dictionary is ready after you open ToriWords once". Since the dictionary is read from the bundle, this appears only if the bundle has no dictionary file at all, and opening the app does not change that. Replace it with "Not in the dictionary" or a neutral line.
2. **Unsupported Apple Translation.** On a device where EN→RU is `.unsupported`, a word without a dictionary hit stays "Translation pending" forever. Android sends such words straight to "No translation found — add your own". Decide whether iOS should do the same.
3. **Share Extension memory.** The extension's peak memory with the full dictionary open has not been measured against the system limit for extensions.
