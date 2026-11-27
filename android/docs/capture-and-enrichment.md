# Capture, dictionary, enrichment and pronunciation

How words get into ToriWords on Android and how they are filled in:
- the capture sheet;
- the shared capture text rules;
- the bundled dictionary;
- on-device machine translation (ML Kit);
- pronunciation (text-to-speech).

Related files:
- [data-model.md](data-model.md): tables, columns and provenance fields.
- [architecture.md](architecture.md): modules, start-up, WorkManager.
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
| Selected text in any app | Selection toolbar → **ToriWords** (`Intent.ACTION_PROCESS_TEXT`, `text/plain`). One tap, or two when the toolbar puts it in its overflow menu; the source app and the OS decide. |
| Shared text or link | Share sheet → ToriWords (`Intent.ACTION_SEND`, `text/plain`). |
| A Chrome page | Text selection (text only, no URL or sentence context) or Chrome's Share (text and/or URL). |
| In-app typing | The Add screen in the main app. |

Not in v1:
- screenshot OCR;
- app shortcuts and direct-share targets;
- capture from streaming-app subtitles. Text works only where the source app allows selection or sharing.

There is no selection-menu tip in the app.

## CaptureActivity

**Manifest:**
- Exported, with intent filters for `PROCESS_TEXT` and `SEND` (`text/plain`).
- Translucent theme, with a Compose `ModalBottomSheet`.
- `excludeFromRecents="true"`, `taskAffinity=""`, `windowSoftInputMode="adjustResize"`.

**Task and process:**
- It lands in the caller's task, so Save and Cancel `finish()` back to the source app.
- It runs **in the app process** and uses the same `store`, `dictionary` and `enrichment` singletons as the app. There is no inbox file and no import step (the iOS Share Extension needs those because it is a separate process).

**Text input:**
- For `PROCESS_TEXT`, the text comes from `EXTRA_PROCESS_TEXT`.
- `EXTRA_PROCESS_TEXT_READONLY` is ignored. The activity never returns replaced text (`setResult(RESULT_CANCELED)`); it only adds a word.
- For `SEND`, the text comes from the split below.

**Start-up:**
- The sheet shows the text immediately.
- It waits for app start-up only for the parts that need data: dictionary lookup, duplicate check, Save.
- On a first-ever launch that is a capture, the dictionary install (below) runs first. The senses area shows a loading state meanwhile.

**Keeping it light:**
- The activity runs no sync, no full replay and no index rebuild itself.
- Follow-up work is **enqueued to WorkManager** after Save: enrichment fill and debounced sync. It survives the activity finishing and the process being reclaimed.

**State and targets:**
- State lives in a ViewModel with `SavedStateHandle`, so rotation, resizing and process death keep the draft. The intent is redelivered after process death.
- Targets: the sheet is visible in ≤ 1 s from a cold start; selection to saved takes ≤ 2 s for a dictionary hit.

### SEND text split

1. `text` = `EXTRA_TEXT` (a `CharSequence`, converted to a plain string). `title` = `EXTRA_SUBJECT`, else `EXTRA_TITLE`, else none.
2. **URL** = the first match of `https?://` followed by non-whitespace in `text`, else in `title`.
   - These trailing characters are trimmed off the match: `. , ; : ! ? ) ] } » " '`.
   - Other schemes are not URLs here.
3. The URL is removed from `text`.
   - The rest is trimmed of whitespace and of one pair of wrapping quotes (`"…"`, `“…”`, `«…»`).
   - If `title` equals the URL, it is dropped.
4. **Remaining `text` is empty:** this is a **link-only share**. The Source comes from the URL and title, the user types the word, and the Context is source-only.
5. **Otherwise:** `text` goes through the capture text rules below, and the URL and title form the Source.

Chrome's "share highlighted text" adds a `#:~:text=` fragment. The URL key drops fragments, so the result is the same Source as the page.

These rules are Android-only. They are covered by Android unit tests, not by shared fixtures.

### Source app

**Finding the caller:**
- The caller package is `callingPackage` when present. For `PROCESS_TEXT` it is reliable: the selection toolbar starts the activity for a result.
- Otherwise it is `Activity.referrer` (the `android-app://<package>` form). For `SEND` through the system share sheet, the referrer normally names the app that started the share.
- The referrer is supplied by the system or the caller and is **best effort**. It is used only for display and for the Source key.

**What is stored:**
- `source.app` = the app's user-visible label (`PackageManager.getApplicationLabel`, for example "Chrome") at capture time, stored as text.
- It is NULL when:
  - there is no caller;
  - the caller is the system chooser or resolver, or ToriWords itself;
  - the package cannot be resolved.

**What is shown:**
- A text-selection capture has no URL, so its Source shows the app name alone. If there is no app name either, no Source is shown.
- "<app> · <domain>" appears only for a Share with a link.

**Source kind:**

| Situation | Kind | ID |
|---|---|---|
| URL present | `web` | deterministic, `v5("source:"+urlKey)` |
| No URL, app label present | `app` | UUIDv7 |
| Title only | `other` | UUIDv7 |
| Neither app nor title nor URL | no Source | — |

Sources without a URL merge by `matchKey(title)` + the stored app name + kind ([sync.md](sync.md#natural-keys)).

## Capture text rules

The same rules apply to every text entry point: the capture sheet (both intents) and the Add field. They are implemented once, in `core`.

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

Otherwise it is a **term**. A sentence source is shown as tappable word chips: the user taps one word, or several adjacent words, to choose the term.

### 3. Reject

Text without any Latin letter cannot be saved. Save is disabled, and the user can edit the text.

### 4. Sentence extraction

For sentence sources only. Keep the one sentence that contains the chosen span.
- **Boundaries:** `.`, `!`, `?` or `…`, optionally followed by closing quotes or brackets, then whitespace. A line break in the original text also counts.
- **Longer than 500 characters:** cut to 500 around the chosen span, at word boundaries, and mark the cuts with `…`.
- **Highlight:** the chosen span becomes the highlight, as an offset and length in **UTF-16 code units** within the stored sentence. These are Kotlin `String` indices directly.

### 5. Entry text

- Term sources: the whole cleaned text.
- Sentence sources: the chosen span.

### 6. Highlight for typed sentences

A sentence typed or edited on the Add screen or in the Entry edit form has no chosen span.
- On save, the highlight is the **first** occurrence of the Entry text in the sentence, compared with match-key folding (case, typographic quotes, apostrophes, dashes) at word boundaries.
- Not found means no highlight. The Context then gets no cloze card, and the recall front does not use it.
- It is recomputed when either text is edited, unless the user moved it.

### Dictionary offers for the chosen term

These are the same on the Add screen and in the capture sheet.

**Base form.** A single inflected word with no headword of its own, but a `form` hit:
- The sheet offers "Save as" with the base form (preselected) and the captured form.
- Phrases are never changed.

**Contained-phrase chips.** A multi-word term, or a typed sentence on the Add screen:
- Dictionary phrases (2–6 words) found inside it, also through the base forms of its words, are offered as opt-in chips. For example, "looked after" offers "look after".
- Tapping a chip makes that phrase the saved Entry text; tapping it again goes back.
- The algorithm:
  1. Tokenise the text's match key (at most 64 tokens).
  2. For each start position, from the longest span (at most 6 words) down to 2, build variants: the words as typed, then with words replaced by their base forms from `form` (non-phrase headwords only). Stop at 16 variants per span.
  3. Keep the variants that are phrase headwords (`is_phrase = 1`), excluding the text's own key.
  4. Order by first position in the text, then longer first.
  5. Show at most 8.

In both cases the **sentence keeps the captured text**: the highlight stays on the span as captured.

## Capture sheet contents and save

### What the sheet shows

**Senses and variants:**
- Dictionary senses and Russian variants, from the `dictionary` module.
- The first variant is preselected.
- The user can multi-select variants or type a translation.

**Machine translation:**
- Shown when the ML Kit model is downloaded (no dictionary hit = the main suggestion; otherwise one extra variant if its translation key differs).
- It never starts a model download.

**Duplicate check:**
- A direct query for the live canonical Entry with the term's match key.
- If found: "Already in your vocabulary" with up to 3 translations in display order.
- If its status is `known` or `paused`, the sheet says so and offers **Resume learning**.
- The same query runs again inside the save transaction, so stale state cannot create a duplicate.

**Tags:** suggestions from live canonical Tags (by `name_key`), plus the sticky tags.

**Source title:** pre-filled from the shared title, else the sticky title.

### Save

Save is one call to the **capture use case** in `store`. It is the same use case the Add screen uses, and it runs as one transaction:
1. **Entry:** find or create it.
   - `origin`: `text_selection` (`PROCESS_TEXT`), `shared` (`SEND`) or `typed` (Add).
   - `created_at` = now.
2. **Senses:** add the picked or typed ones (rank 1, with provenance), skipping translation keys the Entry already has.
3. **Context:** add the sentence with its highlight, or a source-only Context, unless an equal one exists.
4. **Source and Tags:** add or reuse them.
5. **Resume learning**, if chosen: `status = active`, `excluded_reason = NULL`, rank 1.
6. **Enrichment status:** set `enrichment_status = pending` when nothing was picked or typed and the Entry has no translation.
7. **Clocks:** stamp clocks and outbox rows.

### After commit

1. Update the sticky fields.
2. If the Entry is pending, enqueue the `enrichment` work.
3. Rewrite the widget snapshot (debounced).
4. Enqueue the debounced sync.
5. `finish()`.

### Sticky capture fields

- Kept in the DataStore file `capture_sticky`: `updatedAt` (ms), `sourceTitle` (nullable), `tags` (names).
- They are offered again for **30 minutes** after `updatedAt`. After that the sheet starts empty, except for a shared title.
- Written only by the capture sheet on Save, and read only by the capture sheet. The Add screen does not pre-fill from them.
- Not synced, not backed up.

## Editing meanings: suggestion provenance

The Entry edit form lists **suggested meanings** above "Add meaning". These are dictionary variants and the machine translation that the Entry does not have yet, compared by translation key.
- Removing a meaning offers it as a suggestion again.
- Tapping "Add meaning" from read mode adds a blank row only when there are no suggestions to offer.

**Provenance of a picked suggestion:**
- It is saved **with its original provenance**: `translation_src` (`wiktionary` or `mt_mlkit`), `dict_version`, `dict_headword_key`, `dict_sense_ordinal`.
- This holds only while its translation, definition **and** part of speech are all unchanged.
- If the user edits any of the three before saving, the row is saved as a plain user Sense (`user` provenance).
- The draft row keeps the original suggestion and compares all three fields at save time.

## Dictionary

An offline English→Russian dictionary built from Wiktionary.
- It is built by `tools/dictionary/` (see `tools/dictionary/README.md`) and published as a GitHub Release asset.
- Release builds fetch it with `tools/dictionary/fetch.sh`, which checks the committed SHA-256.
- Same inputs give the same bytes.
- Size budget: ≤ 60 MB uncompressed, ≤ 25 MB compressed in the app package.

### Delivery: copied out of the APK

SQLite cannot open a file inside the APK, so Android keeps a compressed copy in the APK and an installed copy. (The iOS app reads its copy in place from the app bundle.)

**Bundled asset:**
- `app/src/main/assets/dictionary/dictionary.sqlite`, a build artefact that is never hand-edited.
- Default AAPT compression applies (~25 MB in the APK).
- With it ships `assets/dictionary/manifest.json`, generated by the build: `{ "dictionaryVersion": "2026.11.1", "sha256": "<hex>", "size": <bytes> }`.

**Installed copy:**
- `noBackupFilesDir/dictionary/dictionary.sqlite`. It is never backed up or transferred.
- The installed hash is kept in the device DataStore.

**Install** runs during app start-up when the bundled `sha256` differs from the installed one, or the file is missing:
1. Stream the asset to `dictionary.sqlite.tmp` in the same directory while hashing.
2. Verify the size and SHA-256.
3. `fsync`.
4. Atomically rename it over the old file.
5. Store the new hash.

**Install failure** (for example, the disk is full):
- Keep the old file, if any.
- Without a dictionary, lookups return nothing, and captures save as `pending`.
- Retried on the next start.

**App update:** `MY_PACKAGE_REPLACED` enqueues the `dictionary-install` work, so the new file is usually installed before the next launch.

**Debug builds:** without the full file, they use the committed sample `ios/Resources/dictionary-sample.sqlite` (same schema).

**Rejected alternative:** an uncompressed asset for a faster copy (+~35 MB installed size). Revisit only if the measured first-capture delay exceeds the 2 s target.

### Access

- Opened by the `dictionary` module with the bundled SQLite driver, **read-only** (`SQLITE_OPEN_READONLY`, `immutable=1` as a URI filename). It does not go through Room.
- The bundled driver provides FTS5 on every device.
- At most 2 reader connections, with a page cache of ≤ 2 MB each.
- The file is replaced only while no reader is open: the install runs before readers start, and an app update restarts the process.

### Schema (read-only, normative)

| Table | Columns |
|---|---|
| `meta` | `key`, `value`: `dictionary_version` (for example `2026.11.1`), dump dates, wiktextract version, licence text, build hash, prune level |
| `headword` | `id`, `text`, `key` (match key), `pos`, `freq_rank` (NULL = unknown; set only for single words), `ipa`, `is_phrase`; index on `key` |
| `sense` | `id`, `headword_id`, `ordinal` (stable within a build), `gloss_en`, `tags` |
| `translation_ru` | `id`, `headword_id`, `sense_id` (NULL = not tied to a sense), `text`, `text_folded`, `origin` (`enwikt` / `ruwikt`), `rank` |
| `form` | `form_key`, `headword_id`, `form_tags` |
| `example` | `sense_id`, `text_en` |
| `related` | `headword_id`, `related_headword_id`, `kind` (`synonym` / `related` / `derived` / `phrase`) |
| `ru_fts` | FTS5 over `translation_ru.text_folded` (lowercased, `ё`→`е`), tokenizer `unicode61 remove_diacritics 0` |

**Pruned builds:** a build may prune `example` and `related` to fit the size budget. Build 2026.11.1 has neither. When `related` is empty, the related-words section is hidden.

**No dictionary row IDs in user data:** provenance is `(dict_version, dict_headword_key, dict_sense_ordinal)` plus a copy of the text, so a new build cannot break user data.

### Queries

All text comparisons are SQLite `BINARY` on UTF-8. There is no in-memory sort by Kotlin `String` comparison: its UTF-16 order differs from UTF-8 byte order. `x'FFFF'` closes a prefix range.

**Autocomplete** (English input, from the 2nd character), up to 8 rows in total:
1. Live canonical user Entries whose `match_key` starts with the typed key (a prefix range on `user.sqlite`'s `(language_pair_id, match_key)` index), ordered by `match_key`, then `id`, up to 3. They are marked "In your vocabulary", and tapping one opens the Entry.
2. Then the dictionary, skipping keys already listed: `SELECT … FROM headword WHERE key >= :p AND key < :p || x'FFFF' ORDER BY freq_rank IS NULL, freq_rank, key, id`.
3. Concatenate in that order. Target: under 10 ms.

**Lookup:**
- `headword WHERE key = :k` (several parts of speech possible), ordered `freq_rank IS NULL, freq_rank, key, id`.
- Forms: `form WHERE form_key = :k` (base-form offer).

**Reverse (Russian input):**
- Applies when the input has a Cyrillic letter (U+0400–U+04FF) and no Latin letter, and at least 2 letters.
- Search-fold it, then match `ru_fts MATCH '"<folded>"*'`.
- One row per headword, ordered by its best matching `translation_ru.rank`, then `freq_rank` (NULL last), `key`, `id`.

**Suggestions per sense:**
- Russian variants, English gloss, part of speech.
- Ordered by sense `ordinal`, then variant `rank`.
- Variants not tied to a sense come after the sense-tied ones.
- Variants are deduplicated by translation key.

**Related words:**
- Up to 8 for the word's headword, or for its base form.
- Ordered by kind (`synonym`, `related`, `derived`, `phrase`), then `freq_rank` (NULL last), then `related_headword_id`.
- One-tap Add saves the item with its rank-1 variant, that sense's gloss and dictionary provenance, and no sentence.
- It adds a source-only Context with a Source of kind `suggested` whose `title` is the origin headword (stored as text, not localised).
- Items already in the vocabulary show as such.
- ✕ hides an item for the current screen visit only.

### Licence

**Settings → About** shows the short attribution row "Dictionary data from Wiktionary, CC BY-SA" ([copy.md](copy.md)).

**Full attribution text:** the Licences screen and the backup file's `attribution` field carry it: "Dictionary data from Wiktionary (en.wiktionary.org, ru.wiktionary.org), contributors, CC BY-SA 4.0, extracted with wiktextract (kaikki.org); modified (filtered, merged, normalised)", with links to the sources and the licence.

**Wiktionary mark:** shown next to Sense values whose provenance is `wiktionary`.

**Exports:**
- A CSV export gets a trailing one-cell attribution row, but only when it contains Wiktionary-derived text.
- The share message carries the attribution too.

## Enrichment

### Principles

1. **Dictionary first, ML Kit as fallback and suggestion.**
   - The dictionary gives several sense-tied variants, definitions and IPA, identical to iOS.
   - Machine translation gives one variant and may differ from iOS (accepted).
2. **Store what the user accepts, and never re-enrich silently.**
   - Accepted values are written to Senses with provenance and synced.
   - Enrichment fills only **empty fields whose last write had rank 0**. A rank-1 (user) field is never written by enrichment again, even if the user emptied it.
3. **No LLMs and no ToriWords server.**
   - Translation runs on the device.
   - Only the ML Kit model download uses the network.

### Pipeline (Add screen and capture)

1. **Normalise:** compute the match key.
2. **Look up:**
   - An exact headword hit, else a form hit, which gives the base-form offer.
   - For multi-word text, contained phrases.
3. **Suggestions per sense,** in the order above.
4. **Machine translation:**
   - With no dictionary hit, ML Kit's translation is the main suggestion, labelled as machine translation.
   - With a hit, it is added as one extra variant only if its translation key differs from every dictionary variant.
   - **Sentence help:** when a sentence is available, "In this sentence: …" shows its machine translation.
     - It runs only when the model is downloaded.
     - It is debounced 600 ms.
     - It is never stored.
5. **User decision:** each picked variant becomes a Sense (rank 1). Provenance per field:
   - `wiktionary` + `dict_version` + `dict_headword_key` + `dict_sense_ordinal`; or
   - `mt_mlkit`; or
   - `user`.
6. **IPA** from the chosen headword is stored on the Entry: rank 0 if automatic, rank 1 if edited.

### Pending Entries and retries

| Situation | Behaviour |
|---|---|
| Dictionary hit, user picks | Senses saved; `enrichment_status = done`. |
| Saved without a chosen translation | `enrichment_status = pending`. **Automatic fill** when the app runs: the first dictionary variant (sense ordinal 0), or the ML Kit result if there is no hit, goes into an automatic Sense with ID `v5("autosense:"+entryId+":0")`, rank 0, with provenance. Then `needs_check = 1` (rank 0) and `enrichment_status = done`. The Entry is listed under **Check translation**. |
| No dictionary hit, model not downloaded or offline | Stays `pending`, with no translation and no cards. Listed under **Needs translation**. Retried later; it does **not** count an attempt. |
| ML Kit failed or returned nothing 3 times (no dictionary hit) | `enrichment_status = unavailable`: "No translation found — add your own", with **Try again**. |
| `unavailable`, and a new source appears (newer dictionary, model downloaded) | Run again on Entries whose translation fields are empty and rank 0. Success sets `done`. |
| A dictionary read error, or a headword without Russian variants | Counts as no hit, so ML Kit gets its chance. |
| User typed a translation, and enrichment finds more | Offered as suggested meanings on the Entry screen; never added automatically. |
| User cleared an automatic translation | The field is now rank 1 and empty, and it stays empty: "No translation yet". |

**Retry mechanics:**
- `entry.enrich_attempts` (local, never synced) counts ML Kit failures.
- Background retries use an in-memory backoff (1, 2, 4 … min), so foreground triggers do not use up the 3 attempts.
- **Try again** and a new source reset the backoff.

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
- the Entry screen is opened; or
- an answer for one of its cards is committed.

**Rules:**
- It is cleared only if it is currently 1, so viewing writes nothing otherwise.
- It is never written with rank 1, so a later automatic fill on another device can raise it again.

### Enrichment work

**Background fills** run in the `enrichment` work: unique, `KEEP`, no network constraint. It may run while the app is in the background.

**Triggers:**
- the app comes to the foreground;
- a capture or Add with nothing picked;
- the model download finishes;
- the dictionary was replaced;
- **Try again**.

**Large backlogs:** many pending Entries are processed in one run.

## ML Kit translation

- `com.google.mlkit:translate`, `TranslateLanguage.ENGLISH` → `TranslateLanguage.RUSSIAN`. The Russian model is about 30 MB.
- Provenance of its output: `mt_mlkit`.

### Model download

**Automatic, on Wi-Fi:**
- The first app start-up, whatever the entry point (a capture-only first start included), enqueues the unique `mlkit-model` work: `ExistingWorkPolicy.KEEP`, `NetworkType.UNMETERED`, exponential backoff.
- Every later start-up re-enqueues it while the model is missing.
- The worker calls `RemoteModelManager.download(TranslateRemoteModel(RUSSIAN), DownloadConditions.Builder().requireWifi().build())`.

**From Settings, on mobile data:** **Settings → Translation → Download** enqueues the same work with `CONNECTED`, expedited, without the Wi-Fi condition.

**Progress:** ML Kit reports no progress percentage, so "Downloading" is indeterminate.

**When the download finishes:** enqueue the `enrichment` work.

**Interactive use never downloads:** the Add screen, the Entry screen and the capture sheet never start a download.

### Model states

Shown in Settings → Translation, together with the dictionary version.

| State | Condition |
|---|---|
| Ready | `isModelDownloaded` is true |
| Downloading | the work is running |
| Waiting for Wi-Fi | the automatic work is enqueued and its `UNMETERED` constraint is unmet |
| Waiting for network | the work started from Settings is waiting for any network |
| Download failed | the work stopped after 5 attempts, or on a non-retryable error (insufficient storage). **Try again** re-enqueues it with `CONNECTED`. |
| Not available on this device | no Google Play services |

- The Settings root row shows "Built-in dictionary" unless the model is ready. The bundled dictionary always works.
- The model state is not shown on Home.

### Adapter

- One `Translator` (`Translation.getClient(TranslatorOptions(EN, RU))`) in the application scope.
- It is created lazily.
- It is closed after 60 s without use, and on `onTrimMemory(TRIM_MEMORY_BACKGROUND)` or stronger.
- `translate()` is called only when the model is downloaded.
- A translate error or an empty result counts as a failed attempt.

### Disclosure

ML Kit sends Google diagnostics and usage data, and there is no supported switch to turn this off. It includes:
- device information;
- available ML hardware;
- the configured source and target languages.

ToriWords keeps ML Kit and discloses this in:
- **Settings → About** (the privacy note);
- the **Play Data safety** form.

Model downloads also come from Google servers.

### Devices without Google Play services

- Translation shows **"Not available on this device"**.
- The `enrichment` work treats a pending Entry without a dictionary hit as finally failed, at once. It goes straight to `unavailable`: "No translation found — add your own". It does not wait for a model that can never arrive.
- **Try again** and a dictionary update still re-run the dictionary step.

## Pronunciation (TTS)

- `android.speech.tts.TextToSpeech`, one instance in the application scope.
- It is initialised lazily and warmed up when Review or an Entry screen opens (engine binding is asynchronous).

### Voice choice

The accent is a per-device setting:
- US → `Locale.US`;
- UK → `Locale.UK`.

**Picking a voice:**
1. Take the `voices` with that locale that are installed (no `KEY_FEATURE_NOT_INSTALLED`) and **do not require a network connection**.
2. Prefer the highest `quality`, then the lowest `latency`.
3. **Default-voice rule:** if the best candidate's quality is below `Voice.QUALITY_HIGH`, and the engine's `defaultVoice` has the accent's locale and is installed and offline, use `defaultVoice` instead. This matches the iOS rule of using the system voice over novelty voices.
4. If no voice has the accent's locale, use any installed offline `en-*` voice.
5. **Network voices are never used:** they would send the spoken text to the engine's server.

**Caching:** the choice is cached per accent, and recomputed when the engine re-initialises or the accent changes.

### No usable voice

This covers no engine, an init error, or no offline English voice.
- The speaker button stays visible but disabled.
- Tapping it explains why. The dialog offers the system voice-data installer (`TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA`) when an activity resolves it; with no engine at all, it has no install button.
- IPA stays visible.

### What is spoken

- **Tap:** the English word or phrase.
- **Long-press:** the sentence.
- **▶ next to a sentence** (Entry screen, card back): speaks that sentence.
- Russian is not spoken in v1.

### Audio

**Audio attributes and focus:**
- `AudioAttributes(USAGE_MEDIA, CONTENT_TYPE_SPEECH)`.
- Before speaking, request audio focus `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`, and abandon it when speech ends. Other audio ducks meanwhile.

**Tap and long-press** always speak, at media volume.

**Auto-play on reveal:**
- A per-device setting, default off.
- It is **skipped while `AudioManager.ringerMode` is silent or vibrate**, so a silenced phone makes no automatic sound.

**Stopping:** speech stops when the card changes and when the screen reaches `onStop`.

**Storage:** audio is generated on demand, and never stored or synced.

## Open questions

1. **First-capture delay on a fresh install.** The one-time dictionary copy (~58 MB) on a mid-range device is not measured yet. If it exceeds the 2 s capture target, ship the asset uncompressed (see [Delivery](#delivery-copied-out-of-the-apk)).
2. **Default-voice quality.** TTS engines differ in the quality of `defaultVoice`. The default-voice rule needs checking on at least a Pixel (Google TTS) and a Samsung (Samsung TTS) device.
