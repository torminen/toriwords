# ToriWords Android — Product spec

What the Android user experiences: features, behaviour rules, edge cases and offline behaviour. The app supports **Android 12 (API 31) and later**.

**The template.** The iOS app on `main` (`ios/`) is the template. Android behaves the same wherever the platform allows. Every deliberate difference is marked **Android difference** below, and all of them are collected in [ios-differences.md](ios-differences.md).

**Related files:**
- vocabulary model, states and merge rules: [domain.md](domain.md);
- screens, layout, motion and haptics: [ui.md](ui.md);
- English and Russian strings: [copy.md](copy.md);
- how it is built: [architecture.md](architecture.md), [data-model.md](data-model.md), [capture-and-enrichment.md](capture-and-enrichment.md), [scheduler.md](scheduler.md), [sync.md](sync.md).

This file contains no storage schemas, APIs or algorithms.

**Name.** The UI writes the product name as **"ToriWords"**, and that is also the launcher label.

**Words used here.** An Entry is a **word** (or phrase). A Sense is a **meaning**. A Context is a **sentence**. Quoted UI strings are the English copy; Russian is in [copy.md](copy.md).

## 1. Goals and principles

**User.** The owner: a native Russian speaker learning English, who meets new words mostly in articles and subtitled series, and finds Anki powerful but inconvenient. Secondary users are other Russian speakers who learn English the same way.

**Goals**
- Be genuinely useful as a daily tool for collecting and reviewing English words and phrases.
- Use the newest stable native technology. When the two goals conflict, usefulness wins.

**Principles**
- **Capture in seconds, from where the word was met,** keeping the sentence and the source. On Android this is one tap from any app's text selection, or the share menu.
- **Zero configuration.** Opinionated defaults; no deck or template design; few settings.
- **Local-first.** Everything works offline, with no account. Google Drive sync is optional and only adds backup and sync between the user's Android devices.
- **Same behaviour on every platform.** Scheduling, duplicates, merging and counts behave identically on Android and iOS. Only suggestions (machine-translation variants) and voices may differ.
- **Calm.** No streaks, XP, levels, leaderboards, guilt messages or promotional notifications.
- **No lock-in.** The user's data is theirs: CSV and JSON export, an open data format, open source.
- **Privacy.** No analytics, tracking or crash-reporting SDKs, and no ToriWords server. The only exceptions are the OS's own crash and performance reports, and the on-device translation library's diagnostics, which are disclosed ([Settings and About](#59-settings-and-about)).

**Product rules that shape every feature**
- **One language pair: Russian → English.** The model allows more pairs later. The UI has no pair choice.
- **Free sources only.** The bundled Wiktionary dictionary (offline from first launch), and on-device machine translation (ML Kit) once its model is downloaded.
- **Cards.** Every reviewable word has a recognition card (English → Russian) and a recall card (Russian → English). Words with a captured sentence also get a cloze card.
- **Two grades, Forgot and Remembered.** No Hard or Easy. The scheduler and its intervals are never shown.
- **Daily load.** 10 new words a day by default (0–50; counts words, not cards). There is no cap on due reviews. The review day starts at 04:00. After a break the app spreads the backlog over about a week.
- **Organisation.** Flat tags; one review queue; no decks.
- **Pronunciation.** The system text-to-speech voice (US by default, UK as a setting) plus Wiktionary IPA. No recorded audio.
- **Related words.** Up to 8, from bundled dictionary data. The same word gives the same suggestions on Android and iOS. The current dictionary build carries no relation data, so the section stays hidden until a build does ([5.13](#513-related-words)).
- **Reminders.** One opt-in daily local reminder, only on days with cards, offered after the first finished session. A home-screen widget.
- **Progress.** Minimal stats: today, vocabulary by stage, 30-day activity, captures.
- **Deletion.** A confirmation, then a short Undo; the deletion takes effect when the Undo closes. Deletion is terminal and wins over concurrent edits and reviews. There is no trash.
- **Settings scope.** Scheduling settings sync. The reminder, UI language, accent and auto-play are per device.
- **Duplicates.** `ё` equals `е` for duplicates and search. Text is displayed as written.
- **Phone-first.** Tablets, foldables and resizable windows get the same adaptive layout.

## 2. Scope

**Android v1 = everything the iOS app on `main` has.** There are no priority tiers. On top of that come the Android-specific capture paths and settings listed under each feature.

| Feature | Section |
|---|---|
| Add a word by typing (autocomplete, base form, Russian → English lookup, contained phrases, sentence translation help) | [5.1](#51-add-a-word-by-typing) |
| Capture from the text-selection menu and the share menu | [5.2](#52-capture-via-text-selection-and-share) |
| Duplicates | [5.3](#53-duplicates) |
| Saving without enrichment, auto-fill, Check translation | [5.4](#54-saving-without-enrichment) |
| Phrases as first-class items | [5.5](#55-phrases) |
| Review: recognition, recall and cloze cards; swipe; undo; catch-up; practice | [5.6](#56-review) |
| Words list and entry screen, including bulk actions and suggested meanings | [5.7](#57-words-and-the-entry-screen) |
| Google Drive sync | [5.8](#58-google-drive-sync) |
| Settings and About | [5.9](#59-settings-and-about) |
| First run, Home, launch animation, live header | [5.10](#510-first-run-home-and-launch) |
| Tags | [5.11](#511-tags) |
| Pronunciation | [5.12](#512-pronunciation) |
| Related words | [5.13](#513-related-words) |
| Daily reminder and home-screen widget | [5.14](#514-reminders-and-widget) |
| Progress | [5.15](#515-progress) |
| Export, restore and device backup | [5.16](#516-export-and-backup) |

## 3. Later (not in v1)

| Item | Note |
|---|---|
| Screenshot / photo OCR capture | DRM streaming apps also block screenshots. |
| Desktop / browser extension | Outside native mobile scope. |
| Anki import (.apkg) and Anki export | The data model is ready ([domain.md](domain.md#future-import-after-v1)). |
| More language pairs | The data model is ready. |
| In-app reader for pasted articles; subtitle file import | — |
| Generated example sentences; curated word sets | The user's own sentence comes first. |
| Filter Words by source; a "Review all now" control in catch-up | Not on iOS either. |
| Reviewing a single tag | One queue in v1. |
| Typed answers, listening and multiple-choice exercises | — |
| Android app shortcuts; review inside the widget; lock-screen widget; Wear OS | — |
| Tablet- and foldable-specific layouts (list–detail panes) | Same adaptive layout in v1. |
| A compact copy for Android's device backup | v1 backs up the vocabulary database as is ([5.16](#516-export-and-backup)). |
| Saved or synced dismissals of related words | Dismissals last for the current screen only. |
| Push notifications | Reminders are local; other devices update when they sync. |
| CSV import | Anki import covers migration later. |
| On-device LLM features | Not planned: no Russian support, device-limited, differs per OS. |
| Recorded human audio | Not planned: licences, coverage, size. |
| Streaks, XP, levels, leaderboards | Not planned. |

## 4. Navigation conventions

- **Back stack.** One back stack starting at Home; there is no bottom navigation bar and no floating action button. Screens have a top app bar with **←**, and system Back (button or gesture) does the same as ← unless a feature says otherwise. Overflow menus use **⋮**.
- **Back order.** Back first closes an open row tray, sheet, dialog or menu, or cancels a card drag. Then it leaves the screen, or asks first where a feature says so.
- **Screen-edge drags.** A drag that starts in the system's edge gesture zone is always system Back, never a review swipe or a row swipe.
- **Feedback surfaces.** The delete **Undo** and row-action undo are snackbars. Confirmations are dialogs.

Presentation is in [ui.md](ui.md).

## 5. Features

### 5.1 Add a word by typing

**Behaviour**
1. **Opening Add.** Add opens from the **"Add a word…"** field at the top of Home and from **+** in the Words top app bar. The field is focused and the keyboard is up.
2. **Autocomplete.** From the second character, the user's English input shows an autocomplete list of matching words and phrases from the bundled dictionary, each with its part of speech and primary Russian translation.
   - Words already in the vocabulary come first, marked **"In your vocabulary"**. Tapping one opens that entry.
3. **Opening the preview.** Picking a suggestion, or confirming the typed text (keyboard action), opens the **preview**, a screen of its own on top of typing, with **Save** in its top app bar. It shows:
   - the word with ▶ (pronunciation), IPA and part of speech;
   - **Translation** variants as checkboxes:
     - dictionary variants first, then the on-device machine translation labelled **"Machine translation"**;
     - the first variant is preselected, and the user can check several, uncheck, or type their own (**"Type a translation (optional)"**);
     - a machine translation equal to a dictionary variant is shown once;
   - the **Definition** of each checked variant, each shown once;
   - an optional **Sentence** (where the user met the word). Its machine translation is shown under it as help ("In this sentence: …"); it is not saved;
   - an optional **Source** title (for example "The Bear S2E3");
   - **Tags**.
4. **Base form.** When the typed word is an inflected form the dictionary knows ("took" → "take", "mortgages" → "mortgage"), the preview offers **Save as** with the base form preselected and the typed form as the alternative. Phrases are not changed.
5. **Saving.** **Save** creates the entry: each checked or typed variant becomes a separate meaning, and unchecked variants are discarded. Every preview field is editable before saving. A field the user filled or edited is never changed by enrichment later.
6. **After Save.**
   - The preview closes by itself, and typing shows the cleared field with **"Saved"**, so several words can be added in a row. Related words for the saved word appear under it ("Related to '<word>'", [5.13](#513-related-words)).
   - If saving fails, **"Something went wrong"** shows and the preview stays.
7. **Hints on the typing screen.**
   - **Under the empty field**, while nothing has been saved in this visit: the Home empty-state card "Build your vocabulary" without its button. It shows on every visit until the first save; nothing is stored.
   - **Widget hint**, after a save, while no ToriWords widget is on the home screen and the hint is not snoozed ([5.14](#514-reminders-and-widget)).
8. **First review.** A new word first appears in review within the daily new-word limit ([5.6](#56-review)).
9. **Back.**
   - ← or Back from the preview returns to typing with the text kept, without a prompt.
   - ← or Back from typing leaves Add at once, without a prompt; typed text is discarded.
10. **Text that looks like a sentence** (more than 6 words, or ending with sentence punctuation; the same rule as capture, [capture-and-enrichment.md](capture-and-enrichment.md)):
    - Typing shows **"Tap the word to save"** with the sentence's words as chips, and **"The text is kept as the sentence."**
    - The user taps one word, or adjacent words for a phrase.
    - **Contained phrases:** the dictionary phrases found in the sentence ("looked after" → "look after") show as chips too. Picking one saves that phrase, with the sentence kept.
11. **Russian typed in the field.** The app offers English candidates for the Russian text from the dictionary. Picking one continues as usual. With no candidates it says **"Type the English word or phrase"**.

**Edge cases**
- **Word already saved.** The preview shows **"Already in your vocabulary"** with **Open word**. Existing meanings show as checked and disabled; new ones can be checked ("Save adds newly checked meanings and the sentence.").
- **Word already saved but marked known or paused.** The preview shows "You marked this as known" or "You paused this word" with "Save adds the sentence and meanings." and a **Resume learning** switch. It applies on Save, and is off by default.
- **Not in the dictionary** (slang, names, new words, many phrases). There is no autocomplete match, and the preview shows the machine translation only.
  - With no machine translation either, the preview shows a reason line and the translation field, and the user types a translation or saves without one ([5.4](#54-saving-without-enrichment)).
  - **Android reason lines** (the model state differs from iOS): the model is not downloaded yet; it is downloading; or machine translation is not available on this phone (no Google Play services).
- **Several meanings** ("bank"): all dictionary meanings are listed with their part of speech, so the user can pick the one they met.
- **Text with only spaces or punctuation:** Save is disabled.
- **Different suggestions on Android and iOS:** acceptable. What the user saves is what is stored.

**Offline**
- Saving always works.
- Autocomplete, dictionary translations, definitions, IPA, base forms, contained phrases and Russian → English lookup work offline from the first launch, because the dictionary is bundled.
- Machine translation (variants and sentence help) works offline once the English–Russian model is on the device ([5.10](#510-first-run-home-and-launch)).

### 5.2 Capture via text selection and Share

**Entry points**
- **Text selection:** select text in any app → **ToriWords** in the text-selection menu.
  - Some apps put ToriWords under the menu's overflow (⋮), which adds a tap. The app cannot control this, and shows no tip about it.
  - **Android difference:** iOS captures through the share menu only, and shows a share-menu tip.
- **Share:** share text or a link from any app's share menu → **ToriWords**.

Both open a compact **capture sheet** over the current app, so the user stays in the app they were reading. The sheet does not appear in Recents. After Save or dismiss the user is back in the source app. Capture never changes the text in the source app, even when that app allows replacing the selection.

**Capture sheet**

The exact text rules (word counting, sentence detection and splitting, markup cleanup, length limits, highlight positions) are shared with iOS and pinned by `spec/fixtures/capture` ([capture-and-enrichment.md](capture-and-enrichment.md)). What they mean for the user:

1. **Short selection** (up to 6 words, not ending with sentence punctuation). The selection is the word or phrase to save. The sentence field is empty; the user can paste or type one. The sheet opens without the keyboard.
2. **Longer selection** (more than 6 words, or ending with sentence punctuation). The selection is treated as the sentence, and its words show as chips under **"Tap the word to save"**. The user taps one word, or adjacent words for a phrase. The sentence is kept, with the chosen text highlighted.
3. **Save as / Phrases.** For the chosen text, the sheet offers the same dictionary choices as Add:
   - **Save as** the base form (preselected) or the captured form;
   - **contained phrases** as opt-in chips under **"Phrases"**. Picking one saves the phrase instead; the sentence keeps the captured text.
4. **Shared link only** (a URL, no text). The page title and URL become the source, and the word field is focused with the keyboard up. Save is disabled until a word is typed. The entry gets the source but no sentence (a source-only sentence record, [domain.md](domain.md#context)).
5. **Source.**
   - **Share with a link** (for example Chrome's Share): the URL and page title are saved, and the source shows as "<app> · <domain>" or the page title.
   - **Text selection:** Android delivers no URL with a selection. The source is the name of the app the text came from (for example "Chrome") when Android reports it, otherwise none. **Android difference:** iOS has no text-selection capture.
   - The user can type or edit a source title. The last used source title and the last used tags are offered again for 30 minutes.
6. **Translation.**
   - The sheet shows the same suggestions as Add: dictionary variants, definitions, IPA and ▶, then the **Machine translation** variant when the model is on the device. **Android difference:** iOS shows no machine translation in its share sheet.
   - The first variant is preselected, so Save right away keeps it.
   - A captured sentence shows its machine translation as help ("not saved").
   - If there is nothing to pick and the user types nothing, the word is saved **pending enrichment**. The app fills the translation automatically later and flags it **Check translation** ([5.4](#54-saving-without-enrichment)).
7. **Tags.** Collapsed by default; the last used tags are offered for 30 minutes.
8. **Save** shows a short **"Saved"** confirmation in the sheet, then closes it and returns to the source app. Target: two taps after the selection for a short selection (the ToriWords menu item, then Save).

**Edge cases**
- **Word already saved.** "Already in your vocabulary", with up to three existing translations. Save attaches the new sentence and source ([5.3](#53-duplicates)).
- **Word marked known or paused.** "You marked this as known" / "You paused this word", with a **Resume learning** switch (off by default). Save attaches the sentence; the word resumes only if the switch is on.
- **Selection in Russian or another script.** The sheet says **"ToriWords saves English words and phrases"** and lets the user edit the text. Save stays disabled until the text contains Latin letters.
- **Selection spanning several sentences.** After the user picks the word, only the sentence that contains it is kept.
- **Sentence longer than 500 characters.** Cut to 500 characters around the chosen word, at word boundaries, with "…" marks.
- **Very large share** (more than 5,000 characters). Only the first 5,000 characters are offered for picking. A URL, if present, is still saved as the source.
- **Line breaks, extra spaces, subtitle markup** (`<i>`, `[music]`, a speaker name before a colon): cleaned for display and saving.
- **Inflected form chosen** ("took off"): Save as offers the base form; the highlight marks what was picked.
- **Separable phrasal verbs** ("take your shoes off"): chips pick adjacent words only. The user picks "take" and edits the text to "take off", or picks a contained phrase if the dictionary finds one.
- **App installed but never opened.** Capture works as usual: the sheet is part of the app.
  - On this very first run the dictionary needs a few seconds to prepare. The text shows at once, and suggestions appear when ready.
  - Machine translation is not available yet. This first run starts the model download (Wi-Fi only).
  - Without a dictionary hit, the word is saved pending enrichment and filled later.
  - **Android difference:** the iOS share extension cannot use the dictionary before the app is first opened.
- **Sheet dismissed** (Back, swipe down, tap outside): nothing is saved.
- **Streaming apps.** Text selection does not work in most video players, so capture from Netflix or YouTube subtitles is not promised. The user types the word instead.
- **Capture while sync is running.** The word is saved locally and syncs shortly after, in the background. The sheet never waits for sync.

**Offline.** Capture never needs the network and never waits for it; saving is instant. Dictionary suggestions work offline, and machine translation works offline once the model is on the device. A pending word shows **"Translation pending"** and is not reviewed until it has a translation.

### 5.3 Duplicates

Identical on Android and iOS. The full rules are in [domain.md](domain.md#normalisation-and-duplicates).

- **The vocabulary never contains the same word or phrase twice.**
  - "Same" ignores: letter case; surrounding punctuation; extra spaces; typographic apostrophes, quotes and dashes. `ё` = `е`.
  - Inflections and spelling variants are different words ("run" ≠ "ran", "colour" ≠ "color").
- **Russian translations** are compared the same way.
- **The same sentence** captured again from the same source (ignoring spaces and quote styles) is not added twice.
- **Repeat capture or repeat add** of an existing word:
  - **"Already in your vocabulary"** shows before saving, with the existing meanings;
  - the new sentence and source are added unless already there;
  - a chosen translation becomes a new meaning only if the word does not have it;
  - learning progress and schedule are unchanged.
- **Editing the text to match another word.** **"'X' is already in your vocabulary"** — "Merge combines meanings, sentences, tags and review history into one word." with **Merge** / **Cancel**.
  - After **Merge**, the merged word opens in read mode.
  - **Cancel** returns to the edit form with the edits kept.
- **The same word saved on two devices before they synced.** After sync there is one word with all meanings, sentences and both review histories. The user is not asked anything.

**Edge cases**
- **Repeat capture of a known or paused word.** The sentence is added, and the app shows "You marked this as known" / "You paused this word" with the Resume learning switch. It never resumes automatically.
- **Repeat capture of a deleted word.** Creates a fresh word with no history (deletion is terminal).
- **Capitalisation that matters to the user** ("US" and "us"): one word; both meanings can be added to it.
- **Merging words whose meanings overlap.** Identical meanings appear once.
- **A word and a phrase containing it** ("take", "take off"): different words.

**Offline.** All duplicate checks run on the device. Duplicates created on different devices merge at the next sync, without asking.

### 5.4 Saving without enrichment

**Suggestions are missing when:**
- the word is not in the dictionary, or has no Russian translation there; and
- machine translation cannot help, because the model is not on the device (not downloaded yet, waiting for Wi-Fi, download failed) or the phone has no Google Play services.

**Behaviour**
1. The user can **always save**: type a translation, or save with none.
2. A word without a translation carries the **Needs translation** marker and appears under the **Needs translation** filter. It is not reviewed until it has a translation. Its second line says why:
   - **"Translation pending"**: not filled yet. The app is still waiting for a source (the dictionary being prepared, the translation model).
   - **"No translation found — add your own"**: enrichment ran and found nothing.
   - **"No translation yet"**: the user cleared the translation or deleted the last meaning. The app does not refill it.
3. **Pending** words are enriched automatically when a source becomes available: when the app opens, or after the translation model is downloaded.
4. Enrichment **only fills empty fields**. It never replaces what the user typed or edited.
5. **Nothing found.** The entry screen shows the warning **"No translation found — add your own"** ("Not reviewed until it has a translation.") with **Add meaning** and **Try again**. The app also retries by itself when a new source becomes available, for example after the model download, or after another device filled it.
6. **Auto-fill of pending captures.** A capture saved without a translation automatically gets the first dictionary variant, or else the machine translation.
   - The word is then flagged **Check translation**: the entry shows the banner **"Check translation" — "Translation added automatically. Check it."**, and the word is listed under the **Check translation** filter until the user opens it or reviews it once.
   - If the app later auto-fills again, the flag is raised again.

**Edge cases**
- **The user typed a translation, and enrichment later finds more.** The typed translation stays the only meaning. Dictionary and machine variants are offered as **Suggested meanings**, never added automatically:
  - on the entry screen, each with **Add**;
  - in the edit form, each with ⊕ ([5.7](#57-words-and-the-entry-screen)).
- **The user deletes an auto-filled translation.** The field stays empty; enrichment never refills a field the user cleared. The word moves to Needs translation with "No translation yet".
- **Enrichment runs on two devices for the same pending word.** One word, one set of meanings.
- **Model download not done or failing.** The app works with the dictionary only, and Settings → Translation shows the state. Words without a dictionary hit stay "Translation pending" until the model arrives.
- **No Google Play services** (machine translation can never be available). Words without a dictionary hit go straight to **"No translation found — add your own"** instead of waiting. **Try again**, and a dictionary update, still re-check the dictionary. **Android difference:** iOS has no such state.
- **Many pending words** (for example 30 captures). Enriched in the background without blocking.

**Offline.** Saving is always offline. Enrichment that needs a download waits and retries silently.

### 5.5 Phrases

- **First-class items.** A phrase (phrasal verb, idiom, collocation, any multi-word expression: "take off", "on the fence", "make ends meet") is saved, listed, searched, reviewed and synced exactly like a single word.
- **Automatic kind.** Word vs phrase is decided automatically: more than one word means a phrase. The user never chooses.
- **Picking a phrase.** In capture or a typed sentence, the user picks a phrase by tapping adjacent word chips, or a **contained phrase** chip.
- **Translation.** Uses the dictionary when it lists the phrase, otherwise machine translation.
- **Filter.** Words has a **Phrases** filter.
- **Review.** The highlight or blank covers the whole phrase as it appeared.

**Edge cases**
- **Phrase containing a saved word:** separate words, not linked.
- **Very long phrase:** allowed when typed or edited. Typed or picked text over 6 words is offered as a sentence first ([5.1](#51-add-a-word-by-typing)).
- **Placeholders** ("one's", "someone", "sth"): saved as typed.
- **Literal machine translation of an idiom:** expected. The user picks or types the right meaning.

**Offline.** Same as single words.

### 5.6 Review

**Starting**
- Home's **Due today** block shows the counts and a **Review** button ([5.10](#510-first-run-home-and-launch)). Review also opens from the daily reminder and from the widget.
- One queue holds everything due. Tags and sources do not split it.
- Scheduling is by review day, never by time of day.

**Cards.** Every reviewable word has these cards:
- **Recognition** (English → Russian). The front shows the word with ▶, its sentence with the word highlighted, and **"Tap to show answer"**.
- **Recall** (Russian → English). The front shows **"Say it in English"**, the Russian translations, and the sentence with the word blanked. There is no speaker on the recall front.
- **Cloze**, for words with a sentence that has the word marked. The front shows the sentence with the word blanked and **"Fill in the missing word"**.
- **Back of every card:**
  - the word with ▶, IPA and part of speech;
  - the translations on one line, each once;
  - each distinct definition once;
  - the sentence with ▶ and its source.
- **Which sentence.** With several sentences, a different one is shown each time. Without a sentence, the card shows only the word or the translations. Recall and cloze use only sentences with the word marked; when none has it, recall shows the translations only.
- **Session header:** **✕**; the position ("2 / 17"); **↶** when an answer can be undone; and **⋮** (Edit, I already know this, Pause, Delete).

**Grading**
- After the flip: **Forgot** and **Remembered**.
- **Swipe** duplicates the buttons, and only after the flip: **right = Remembered**, **left = Forgot**. Before the flip, swiping does nothing.
  - The swipe can start anywhere on the card, including a scrolling back; the first movement decides between moving the card and scrolling.
  - A drag that starts in the screen-edge gesture zone is system Back, not a grade.
- **Feel.**
  - The card follows the finger and tilts, with "Remembered →" / "← Forgot" labels beside it.
  - Past the grading angle a haptic tick says the release will count, and a softer tick says it stopped counting.
  - Released past the angle, the card grades and flies off to its side; otherwise it springs back.
  - The buttons send the card off the same way. Input is ignored while a card is flying.
  - The next card appears once the previous one has left.
  - Exact values: [ui.md](ui.md).
- **Swipe demo (once).** On the user's first flipped card ever, the card nudges right (Remembered), then left (Forgot), then springs back. It is never shown again (device-local), and is skipped when animations are off.

**Undo last answer**
- **↶** is visible only while there is an answer that can be undone; otherwise it is hidden, not disabled. It undoes only the last answer and brings its card back.
- The last answer stays undoable until the next answer or the end of the session; only then is it saved to the review history, permanently.
- When the app goes to the background or is closed normally, the answer is saved.
- If the app crashes, or is force-stopped while on screen, an answer that was still undoable is lost (that one answer only).

**Card actions** (⋮): **Edit** opens the edit form and returns to the same card; **I already know this**; **Pause**; **Delete** (confirmation, then Undo). These change the word as anywhere else, and its cards leave the session.

**Session**
- **New words** are mixed in among due reviews, up to the daily new-word limit (default 10).
  - The limit counts **words**: a new word uses a slot when its first card is introduced, and its other cards on later days do not use slots.
  - Example: 20 new words waiting, limit 10. Day 1 introduces words 1–10. Day 2 brings their next cards, plus words 11–20.
- **One card per word per day**, at most.
- **Forgot re-show.** A **Forgot** card comes back a few cards later the same day, until it is remembered once. This holds also after closing and reopening the app, and on the user's other devices after sync.
- **Leaving** (✕ or Back) at any point keeps every answer given, with no confirmation. If a card is being dragged, Back first cancels the drag.
- **Finished screens.** **Done** is the primary button on each of them:
  - **All done for today:** "N cards reviewed · M remembered · K new words" and "Next review: tomorrow" (or "in N days"). Remembered counts cards whose first answer in this session was Remembered.
  - **Nothing to review today:** the title, the next-review line when something is scheduled, and Done.
  - **Learn more new words** (secondary button above Done) appears when new words are waiting and the daily limit is above 0. It adds one more batch of the daily limit, for this session only, and changes no setting. Repeated taps add more batches.
- **Reminder offer.** After the user's first finished session ever, the reminder offer appears over the finished screen ([5.14](#514-reminders-and-widget)).

**Practice today's words**
- **Where.** Opened from **Progress → Today → Practice today's words**. The button, and the footer **"Doesn't change your schedule."**, show only once at least one card has been answered today.
- **Which cards.** Every card answered today, of words that are still active (not paused, marked known or deleted). They are shuffled and shown **once each**: Forgot does not bring a card back.
- **Header:** **"Practice · 2 / 5"**. Cards, flip, swipe, buttons, ↶, ▶ and the ⋮ actions work as in Review. The ⋮ actions do change the word.
- **Answers are not stored.** No review history, and no change to due days, stages, today's counts, Home, the widget or the reminder. Nothing syncs.
- **Leaving.** ✕ or Back leaves at once.
- **End:** **"Practice done"**, "N cards · M remembered", **Done**. There is no next-review line, no Learn more new words and no reminder offer.
- **Repeat.** Opening practice again repeats the same set in a new order.

**Daily load and catch-up**
- **Day start.** A review day starts at **04:00 local time**, a constant.
- **Catch-up.** After a break, when the backlog is much larger than the user's normal daily load (computed from recent history), the app enters catch-up:
  - the Due today block on Home shows **"Welcome back — N cards are waiting. We'll spread them over about a week."** under the counts;
  - each day shows a manageable, shrinking share of the backlog, most at-risk cards first;
  - new words pause until catch-up ends.
- **No catch-up control.** There is no "Review all now" control (as on iOS).
- **No cap** on due reviews on a normal day.
- **Same numbers everywhere.** The numbers are defined once in [scheduler.md](scheduler.md), so Home, the widget, the reminder and iOS show the same counts.
- **Calm.** No guilt messages, no streaks.

**Edge cases**
- **Word edited mid-review:** the card shows the edit at once; the schedule is unchanged.
- **Word deleted or excluded mid-review:** its cards leave the queue.
- **Same card reviewed on two devices offline:** both answers count, and the due day is recomputed from all answers, identically on Android and iOS.
- **Word deleted on another device while reviewed here:** after sync the word is gone, and the answer given here is dropped (delete wins).
- **Time zone change:** "today" follows the device's current time zone; answers keep the zone they were given in.
- **Device clock wrong:** answers are still recorded.
- **Long sentence or large font:** the card scrolls, and the word stays highlighted.
- **Rotation, split screen, folding:** the session continues on the same card, with its flip state.
- **Word without translation:** no cards ([5.4](#54-saving-without-enrichment)).
- **Thousands of due cards:** catch-up applies.
- **New-word limit 0:** reviews only; new words wait.
- **Nothing added yet** (for example review opened from the widget): **"Add words to start reviewing"** with **Add a word**.

**Offline.** Fully offline: the queue, answers, scheduling and summary. Answers sync later. Due counts on two devices may differ until they sync.

### 5.7 Words and the entry screen

**List** (Words, from the Home top app bar or **All words ›**)
- **Rows and count.** All words, newest first, with a count line ("214 words · newest first", "· A–Z", "· next due first"). Each row shows:
  - the word or phrase;
  - a second line: the primary translation, or the translation state for words without one;
  - a stage marker: **New**, **Learning**, **Known well**, **Known**, **Paused** or **Needs translation**. The rule is in [domain.md](domain.md#entry).
- **Search** ("Search words, translations, sentences"), plus a horizontally scrolling row of filter chips:
  - **All**, **Needs translation**, **Check translation**, **Phrases**, **New**, **Learning**, **Known well**, **Known**, **Paused**, **Tag**;
  - there is no source filter (as on iOS).
- **Sort** (top app bar): **Newest**, **A–Z**, **Next due**.
- **+** in the top app bar opens Add.
- **Row swipe left:** **I already know this**, **Pause**, **Delete**. Paused and known rows offer **Resume learning** instead of the first two.
  - Only one row is open at a time. Scrolling, tapping elsewhere or Back closes it; Back closes an open row before it leaves Words.
  - The same actions are on the entry's ⋮ menu, and as TalkBack custom actions on the row.

**Search**
- Finds words by English text, Russian translation, definition and sentence text.
- Ignores case and typographic variants; `ё` matches `е`.
- Results update as the user types.
- **No results:** **"No words match '…'"** with **Add '…'**, which opens Add with the text.

**Bulk actions**
- **Entering select mode:** **Select** in the Words ⋮ menu, or a long-press on a row.
- **Top bar:** Cancel, "N selected", **Select all** / **Deselect all**.
- **Bottom bar:** **Tag**, **Known**, **Pause**, **Delete**. When every selected word is Known or Paused, **Resume learning** replaces Known and Pause.
- **Tag** adds the chosen tags to the selected words ("Adds tags to N words. Tags they already have stay."). It never removes tags.
- **Delete** asks "Delete N words?" ("They are removed with their review history on all your devices."). The snackbar "N words deleted" with **Undo** follows.
- Row swipes are off while selecting. Select mode ends after each action.

**Entry screen**
- **Read mode** shows:
  - the word with ▶ and IPA;
  - a **Wiktionary** mark when data came from Wiktionary, linking to the attribution;
  - **Meanings** in order (translation, part of speech, definition). Meanings with the same definition and part of speech show as one row, with their translations comma-separated, each once; a meaning without a definition keeps its own row;
  - **Suggested meanings** (dictionary and machine variants not yet added), each with **Add**;
  - **Sentences**, each with its source; a web source opens the page in the browser;
  - **Tags**;
  - **Note**;
  - **Learning:** stage and "Next review: in 3 days" per card direction, with no intervals or scheduler numbers;
  - **Related words** ([5.13](#513-related-words)).
- **Top app bar:** **✎** (edit) and **⋮** (**I already know this**, **Pause**, **Delete**; or **Resume learning**).
- **Translation states:**
  - **No translation found:** a warning with **Add meaning** and **Try again**;
  - **Translation pending:** **Add meaning**;
  - **Check translation:** a banner ([5.4](#54-saving-without-enrichment)).
- **Edit mode** (✎) is a full-screen form with **✕** and **Save**. It contains:
  - text and IPA;
  - meanings, each with translation, part of speech and definition. Meanings can be deleted and reordered by dragging; TalkBack gets Move up / Move down;
  - **suggested meanings:** the dictionary and machine variants not yet in the form, each with ⊕, between the meanings and **Add meaning**. Machine variants carry the "Machine translation" label. Tapping one adds it as a meaning; it keeps its dictionary origin unless the user edits it. Removing a meaning offers it again;
  - **Add meaning** (a blank row);
  - sentences with sources, and **Add sentence**;
  - tags, note, and **Delete word**.
- **Add meaning from read mode** opens edit mode. It adds a blank row only when there are no suggestions to pick.
- **Unsaved changes:** ✕ or Back asks **"Discard changes?"** (**Keep editing** / **Discard**). With no changes, edit mode closes at once.

**Actions**
- **I already know this:** the word leaves review and stays listed as **Known**. It counts as known in Progress.
- **Pause:** the word leaves review and stays listed as **Paused**.
- **Resume learning:** continues from the existing history.
- **Delete:**
  - confirmation "Delete '<word>'?" — "It is removed with its review history on all your devices.";
  - then the snackbar "'<word>' deleted" with **Undo**;
  - the deletion takes effect, and syncs, only when the snackbar disappears. Closing the app during the Undo window applies it; a crash in that window does not (the word stays);
  - afterwards it cannot be reversed.

**Edge cases**
- **Deleting the last meaning:** allowed; the word moves to Needs translation ("No translation yet").
- **Editing the text of a reviewed word:** history is kept.
- **Deleting the sentence a card uses:** the card uses another sentence, or none.
- **Word deleted on another device while open here:** after sync, **"This word was deleted on another device"**, and the screen closes. Unsaved edits are dropped.
- **Large vocabulary** (10,000+ words): the list and search stay responsive.
- **Rotation, window resize or a language change while editing:** unsaved edits are kept.

**Offline.** Everything works offline; changes sync later.

### 5.8 Google Drive sync

**Android difference.** iOS syncs through the user's private iCloud automatically. Android syncs through the **Google Drive app data folder**: a hidden, app-private area of the user's Google Drive that the user turns on in Settings. There is no ToriWords account and no ToriWords server. Android and iPhone do not sync with each other; the JSON backup moves words between them ([5.16](#516-export-and-backup)). Merge behaviour is identical on both platforms ([domain.md](domain.md#sync-requirements)). Mechanism: [sync.md](sync.md).

**Without sync**
- The app is complete without sync; all data stays on the device.
- Nothing asks the user to turn sync on outside **Settings → Google Drive sync**, which explains it in one line: "Your words are stored on this device. Turn on Google Drive sync to back them up and sync between your Android devices. Optional."

**Turning sync on**
- **Turn on Google Drive sync** opens the system Google account picker and consent, to let ToriWords use its own hidden folder in that Drive. No ToriWords account is created and no email is stored.
- **Cancelled or failed** (closed, no connection, permission denied): sync stays off, nothing changes, and no message is shown.
- **After turning on:** everything on the device is uploaded and merged with what that Drive already has, then kept in sync in the background. Nothing is asked, and no summary is shown.
- **Turn off Google Drive sync:** asks "Turn off sync?" — "Your words stay on this phone and in Google Drive." Sync stops; the words stay on the device and the Drive copy stays. Turning sync on again merges silently.
- **Another Google account** chosen later: the local words merge silently into that Drive.

**While sync is on**
- **When it syncs:** automatically after changes, when the app opens, and periodically in the background (Android decides the exact background timing). **Sync now** is in Settings → Google Drive sync. There is no push.
- **Shown:** the Google account name (as the system reports it; not stored).
- **Status:**
  - **"Synced N min ago"**;
  - **"Syncing…"**;
  - **"Waiting for network"**;
  - **"Google Drive storage is full"**;
  - **"Check your device time"**;
  - **"Google Drive access was removed"**: the user revoked access; words stay; **Turn on Google Drive sync** is offered again;
  - **"Drive data was deleted"**, with **Back up this device again**.
- **No choices for the user.** The user is never asked to choose between this device and the cloud. Conflicting edits resolve per field: the most recent change wins, and an automatic fill never beats a user edit. Delete wins over edits.

**Scenarios**

| Scenario | What the user sees |
|---|---|
| Turn on with local words, empty Drive | The local vocabulary uploads; status "Synced". |
| Drive already has words (a second Android device used offline first, or a reinstall) | Merged automatically. The same words become one word with all meanings, sentences and review history. No question, no summary. |
| Second device, fresh install | Turn on sync with the same Google account and the vocabulary downloads. The app is usable during the download; progress shows in Settings → Google Drive sync. |
| Same word captured, edited or reviewed on two devices offline | One word; the most recent edit wins per field; both answers count. |
| Deleted on one device, edited or reviewed on another | The deletion wins. The deleted word's content is also removed from Drive. |
| **Delete Drive data…** (Settings → Google Drive sync) | Confirmation "This deletes your words from Google Drive. Your other devices keep their copies but stop syncing." The words stay on this phone. Needs a connection; offline it says so and changes nothing. |
| Drive data deleted elsewhere (another device, or Google Drive → Manage apps) | This device keeps its words, stops syncing and shows "Drive data was deleted" with **Back up this device again**. |
| **Remove all data from this device** (Settings → Data) | With sync on, the warning says the words stay in Google Drive and come back at the next sync, and how many unsynced changes would be lost ([5.9](#59-settings-and-about)). |
| Words on an iPhone | Not synced with Android. Export a JSON backup on one, and restore it on the other. |

**Edge cases**
- **App updated on one device but not another:** older versions keep syncing; fields they do not know are kept unchanged.
- **Very large first upload:** runs in the background and resumes after interruptions.
- **Device clock wrong:** never loses answers or creates duplicates. If the clock is off by more than an hour, the status asks to fix the device time.
- **Phone without Google Play services:** the screen says **"Not available on this device"**, has no button, and the app works locally. **Android difference.**
- **Phone restored from a device backup or transfer:** the vocabulary may come back, and sync stays on. If the same Google account is on the new phone, sync resumes by itself and the data merges. Otherwise the status is **"Google Drive access was removed"**, and the user turns sync on again.

**Offline.** Everything except sync itself, turning sync on, and Delete Drive data works offline.

### 5.9 Settings and About

Settings are short; the defaults are meant to be right. The review-day start (04:00) and the scheduler parameters (including desired retention) are not shown.

**Root**, in order: **Learning**, **Reminders**, **Pronunciation**, then **Translation**, **Language**, **Google Drive sync**, **Data**, **About**.

| Row | What it does | Default | Scope |
|---|---|---|---|
| New words per day | Its own screen: a −/+ control "N new words a day", 0–50, with the footer "Counts words, not cards: each new word brings its cards. Applies on all your devices." | 10 | Synced |
| Daily reminder | Switch. While on, a **Time** row opens the time picker ([5.14](#514-reminders-and-widget)). | off, 19:00 | Per device |
| Widget | Opens the **Widget** help screen ([5.14](#514-reminders-and-widget)). | — | — |
| Accent | Its own screen: **US English** / **UK English**, with a footer saying words are spoken with the phone's English voice and that the setting applies to this device only. | US | Per device |
| Auto-play on reveal | Switch. | off | Per device |
| Translation | The row value is **"Ready"** when the translation model is on the device, otherwise **"Built-in dictionary"**. Opens the Translation screen. | — | Per device |
| Language | App language (see below). | System | Per device |
| Google Drive sync | The sync screen ([5.8](#58-google-drive-sync)); the row value is the sync status. | off | Per device |
| Data | **Export**; **Restore from backup**; **Tags** (with the tag count); **Remove all data from this device**. | — | — |
| About | Version, source code, licences, attribution, privacy. | — | — |

**Translation screen.** **Android difference:** ML Kit replaces Apple Translation, and its model has its own states. Explains: "Translations for new words come from the built-in dictionary first, then from on-device translation on this phone." Then:
- **On-device translation** (English–Russian model, about 30 MB). States:
  - **Ready**;
  - **Downloading…** (no percentage: the download reports none);
  - **Waiting for Wi-Fi**, with **Download now on mobile data**;
  - **Waiting for network** (a download started on mobile data, no connection yet);
  - **Download failed**, with **Try again** (for example not enough storage), which downloads over any connection;
  - **Not available on this device** (no Google Play services).
- **Dictionary (Wiktionary): Bundled.**
- The model status shows only here. Home shows no download indicator. Add and capture show a reason line only when a word has no suggestions.

**Language**
- The app follows the system language when it is Russian or English, otherwise English.
- It can be overridden for this app only, per device:
  - **Android 13 and later:** the Language screen shows the current language and leads to the system's per-app language setting, which Android keeps;
  - **Android 12:** an in-app choice **System / English / Русский**, kept by the app. It carries over to the system setting after an upgrade to Android 13.
  - **Android difference:** iOS always uses the system setting.
- Changes the interface only ("Changes the interface only. Your words, sentences and translations stay as they are.").

**Data**
- **Export** and **Restore from backup**: [5.16](#516-export-and-backup).
- **Tags**: [5.11](#511-tags).
- **Remove all data from this device.** A red row with a confirmation:
  - **sync off:** "All your words, review history and tags are deleted from this device. This can't be undone.";
  - **sync on:** "Your words are deleted from this device. They stay in Google Drive and come back at the next sync, unless you delete Drive data in Settings → Google Drive sync.", plus "N unsynced changes will be lost." when there are any.

**About**
- **Version**, and **Source code** (the GitHub repository).
- **Licences:** dictionary data (Wiktionary, kaikki.org / wiktextract, CC BY-SA 4.0) and open-source libraries.
- **Attribution:** "Dictionary data from Wiktionary, CC BY-SA", linking to the licence. Words with Wiktionary data show the **Wiktionary** mark on the entry screen, which links here.
- A note that the ToriWords name, logo and app icon are not covered by the open-source licence.
- **Privacy.** Says:
  - the vocabulary is stored on this device and, when Google Drive sync is on, in the app's hidden folder in the user's Google Drive;
  - nobody else, including the developers, can read it;
  - there is no ToriWords server;
  - there are no analytics, tracking or crash-reporting SDKs, and the app collects no usage data;
  - **on-device translation:** the translation model is downloaded from Google, and Google's translation library sends diagnostic and usage information to Google;
  - only Android's own crash and performance reports exist otherwise.

  The Google Play Data safety form says the same. **Android difference:** iOS uses Apple Translation and has no such disclosure.

**Edge cases**
- **System or per-app language changes:** the app switches; an open edit keeps its unsaved changes.
- **New-word limit lowered** below what was already introduced today: no more new words today; nothing is taken back.
- **Synced settings changed on two devices:** the most recent change wins.

**Offline.** All settings work offline, except downloading the translation model and the Drive actions.

### 5.10 First run, Home and launch

**Launch**
- The system splash shows only the app's background colour. The ToriWords mark then grows in at the centre:
  1. the W (the grass) appears;
  2. the T's stem rises through it;
  3. the branch unfurls from the top of the stem;
  4. the leaf unfolds at its end.
- A short rolling haptic ends as the leaf opens.
- The animation and the haptic play each time the app starts. Returning to the app while it is still running shows Home directly.
- The finished mark holds briefly, even when the data is already ready.
- If the app is still loading after that, a dim band sweeps across the mark until it is ready. Then the mark fades out and Home appears.
- **Animations off** (system setting): the finished mark fades in, the haptic plays at once, then the same hold and fade.
- No spinner. TalkBack reads "ToriWords".
- If the data cannot be opened: **"ToriWords could not open its data"**.
- Timings and the haptic pattern: [ui.md](ui.md). Haptic mechanism and fallback: [architecture.md](architecture.md).

**Home**
- **Layout.** One Home screen; no bottom navigation bar, no floating action button.
  - The top app bar holds the ToriWords mark and name, then **Words** and **Settings**.
  - Below it, the **"Add a word…"** field opens Add.
  - No search on Home (search is in Words); no sync or download indicators.
- **Live header.** Tapping the mark or the name is decorative and navigates nowhere:
  - a gust sways the tree and the grass, with a light haptic tap, and a small wave runs along the letters of "ToriWords";
  - taps add to the swing;
  - every fifth tap the leaf falls; the next tap grows a new one;
  - the movement follows only the user's own tap, so it plays even with animations off;
  - TalkBack reads the header as "ToriWords".
- **Home with words shows:**
  - the **Due today** block;
  - **Recently added**: the 5 newest words with their second line; a tap opens the word;
  - **All words ›**, which opens Words.
- **Due today block.** The whole block except the Review button is one tap target with "Due today ›" and press feedback.

  | State | Block shows | Tap on the block opens |
  |---|---|---|
  | Due | "12 to review · 5 new" (a zero part is left out: "5 new", "12 to review"); in catch-up also the Welcome back line; the **Review** button | Progress |
  | All done today | "All done for today" and "Next review: tomorrow" / "in N days" | Progress |
  | Nothing due (nothing answered today) | "Next review: tomorrow" / "in N days", or "Nothing to review today" when nothing is scheduled | Progress |
  | Words exist but none is reviewable, and at least one needs a translation | "N words need a translation" (N ≥ 1) | Words, filtered to Needs translation |
  | No words | No block; the empty state instead | — |

  - **TalkBack.** The block is one button: "Due today, 12 to review · 5 new" (or "All done for today, next review tomorrow", and so on). Its hint is "Opens your progress." ("Opens words that need a translation." in the none-reviewable state). The Review button is separate, with the hint "Starts today's review.".
  - **Every word paused or marked known** (nothing reviewable and nothing needs a translation): the block shows the nothing-due state, "Nothing to review today", or "Next review: …" when something is scheduled, and a tap opens Progress. It never shows "0 words need a translation".
- **Back** on Home leaves the app, as usual on Android.

**First launch**
- No sign-in screen, no onboarding carousel, no language-pair choice. The app opens on Home.
- **Empty state:** "Build your vocabulary" — "Words you add come back for review just before you forget them.", followed by:
  - **Type it** — tap "Add a word…" above;
  - **From any app** — select text → ToriWords. **Android difference:** the iOS line goes through Share;
  - "Works offline: the dictionary is built in.";
  - **Add your first word**, which opens Add.
- The same card without the button is the hint under the empty Add field.
- **No sync mention.** The empty state never mentions sync, also after a reinstall. To restore words the user turns on Google Drive sync in Settings, or restores a backup.
- **Dictionary:** bundled, offline from the first launch.
- **Translation model.** **Android difference:** iOS downloads translation language data through the system.
  - The first start of the app, whatever triggered it (a capture-only first start too), starts downloading the English–Russian model (about 30 MB) automatically, **on Wi-Fi only**, without asking.
  - Later starts retry while the model is missing.
  - On mobile data the user can start it from Settings → Translation.
  - Until the model arrives, the app uses the dictionary only, and pending words are filled once it does.
- **Notifications** are not requested at first launch.

**Empty states elsewhere**
- **Review, nothing added yet:** "Add words to start reviewing", with **Add a word**.
- **Review, nothing due:** "Nothing to review today" ([5.6](#56-review)).
- **Search with no results:** offers to add the search text.
- **Progress with an empty vocabulary** (it became empty while Progress was open): the "Build your vocabulary" state with **Add a word**.

**Edge cases**
- **Device language neither English nor Russian:** English UI.
- **Storage almost full:** the model download fails with **Download failed**; the rest of the app works.

**Offline.** The first run works fully offline; only the model download needs the network.

### 5.11 Tags

- **Optional.** A word can have any number of tags, and nothing asks for them.
- **Where tags are added:** on the Add preview, in the capture sheet (collapsed by default), in entry edit mode, and with bulk **Tag**.
  - Typing suggests existing tags with their counts, plus **Create tag "…"**.
- **Sticky tags.** The capture sheet offers the last used tags for 30 minutes, like the source title.
- **Filter.** The **Tag** chip in Words opens **"Filter by tag"**:
  - checkable tags with counts, **Clear**, and **Show N words**;
  - with several tags selected, the filter shows words that have **any** of them;
  - the chip then reads "work" or "work +1".
- **Settings → Data → Tags** lists tags alphabetically, with word counts:
  - tap → rename;
  - delete asks first: "Delete tag '<tag>'?" — "It is removed from N words. The words stay.";
  - empty: "No tags yet. Add tags to words in Add or when editing a word."
- **Review** is always one queue.

**Edge cases**
- **Names differing only in case or spaces** ("Work", "work "): the same tag. Punctuation counts ("C#" ≠ "C").
- **Renaming to an existing name:** "'work' already exists", and the two merge after **Merge**.
- **Deleting a tag:** removes it from words; the words stay.
- **Same tag created on two devices offline:** one tag after sync.

**Offline.** Fully offline; tags sync.

### 5.12 Pronunciation

**Behaviour**
- **Where ▶ appears:** on the Add and capture preview, the entry screen, the recognition front and every card back. It plays the English word or phrase with the phone's English text-to-speech voice.
- **Sentences.** A long-press on the word's ▶, or ▶ next to a sentence, plays the sentence.
- **IPA** from Wiktionary shows under the word when available; the user can edit it.
- **Accent:** US English by default; UK English as a per-device setting.
- **Auto-play on reveal:** off by default; when on, the word plays as the card flips.
- **Volume.** A tap on ▶ always speaks, at media volume, even when the ringer is on silent or vibrate. Auto-play stays silent while the ringer is on silent or vibrate.
- No recorded audio.

**Voices.** **Android difference:** Android voices depend on the phone's speech engine.
- **Only voices that work offline are used.** Online voices would send the word to the speech engine's server.
- When the accent's best offline voice is only basic quality, the phone's standard voice for the accent is used if it works offline. Higher-quality offline voices are preferred.
- **No offline voice for the chosen accent:** another offline English voice is used silently.
- **No offline English voice at all:** ▶ looks disabled. Tapping it opens **"No English voice"** with **Install voice data** (the system voice installer) and **Not now**. With no speech engine at all there is nothing to install, so the dialog shows the explanation and **OK**.
- IPA stays visible either way.

**Edge cases**
- **Voices differ between phones and platforms:** acceptable.
- **Symbols or abbreviations:** read as the system voice reads them.
- **Russian translations:** not spoken.

**Offline.** Works with an installed offline voice. IPA is stored on the word.

### 5.13 Related words

- **Where they appear.** After saving a word in Add ("Related to '<word>'"), and on every entry screen. Up to 8 related English words and phrases: synonyms, related and derived terms, and common phrases containing the word ("mortgage" → "mortgage rate", "remortgage", "loan").
- **Each row:**
  - the word and its primary Russian translation;
  - **+ Add** saves it with that translation and normal enrichment, in one tap. The saved word has no sentence; its source is "Suggested from '<word>'";
  - **✕** hides it for this screen only. Nothing is stored or synced.
- Tapping a row opens a preview with ▶, part of speech, translation, **Add to my words** and **Close**.
- Words already in the vocabulary show **"✓ In vocabulary"** and cannot be added.
- The same word gives the same suggestions on Android and iOS (bundled data).

**Edge cases**
- **No relations known** (common for slang and phrases): the section is hidden.
- **Dictionary build without relation data.** A dictionary build may leave relations out to fit its size budget. The current build (2026.11.1) has none, so the section is hidden for every word, on Android and on iOS, until a build includes relations ([capture-and-enrichment.md](capture-and-enrichment.md)).
- **All suggestions already saved:** "You have all related words".
- **Quality.** Wiktionary relations are narrower than real topics ("down payment" is not offered for "mortgage"). Accepted.

**Offline.** Fully offline; the lists ship with the app.

### 5.14 Reminders and widget

**Daily reminder**
- **Off by default.**
- **The offer.** After the user's first finished review session, the app offers it once in a bottom sheet:
  - **"Remind you to review every day?"** — "Only on days when cards are due. No streaks.";
  - a reminder time (default 19:00, 12/24 h per the device setting), with a note that it arrives around that time;
  - **Turn on reminder** / **Not now**.

  Back, swiping the sheet down or tapping outside it counts as **Not now**. The reminder is also in Settings → Reminders.
- **Permission.**
  - **Android 13 and later:** turning the reminder on asks for the notification permission at that moment, never at first launch. Each later turn-on asks again, as long as Android still shows the request.
  - **Android 12:** no permission request.
  - **Denied, or notifications turned off for the app:** the switch stays on, and Settings → Reminders shows **"Notifications are off for ToriWords"** with **Open system settings**. The app never asks on its own. No message appears right after a denial.
- **Delivery.** One local notification per day, **around** the chosen time: usually within a few minutes, and later when the phone has been idle. **Android difference:** iOS delivers at the exact minute.
- **Content.** The notification reads **"12 to review"**, the same count as Home's Due today, including new words. A day with only new words also gets a reminder. Tapping it opens Review.
- **When it does not appear.** No notification on a day with nothing due, or once everything due today is done. If the reminder is showing and the user then finishes today's queue in the app, it is removed. No push server.

**Widget**
- **Home-screen widget**, resizable (2×1 and 2×2 cells). **Android difference:** there is no lock-screen widget on Android.
- **Content:**
  - **"12 to review · 5 new"** (a zero part is left out);
  - the larger size adds **"Tap to start reviewing"**;
  - nothing due today: **"Next review: tomorrow"**, or the date ("Next review: Mon, 30 Nov"); never a time;
  - **"Open ToriWords"** when nothing is scheduled, when no word is reviewable or there are no words, when it was placed before the app was ever opened, or when it has not updated for 7 days.
- Tapping it opens Review (or the app, for "Open ToriWords").
- **Updates.** The count is the same as Home's. It updates after reviewing, after sync, and at the 04:00 day start; on Android the day-start update can come a little late, at the latest when the phone is next used.
- **Colours.** The fixed ToriWords palette (light and dark), not wallpaper colours.

**Widget hint**
- **On Add, after a save,** while no ToriWords widget is on the home screen and the hint is not snoozed, a tip appears:
  - **"Add the ToriWords widget"** — "Today's cards on your home screen: touch and hold an empty area, tap Widgets, then find ToriWords.";
  - **Not now** hides it for 24 hours. The until-time is device-local.
- **After placing.** Once a ToriWords widget is placed, the hint no longer shows on Add. Removing the widget brings it back after the next save.
- **Settings → Reminders → Widget** opens a screen titled **Widget**, with the same tip and no Not now.
- **Add widget button.** **Android difference:** iOS can only describe the steps.
  - **Where:** wherever the launcher can place a widget on request, both places get an **Add widget** button between the tip and the text steps. The text steps always stay.
  - **When checked:** each time the hint or the screen is shown. On launchers that cannot do it, there is no button.
  - **Tapping it** shows the launcher's own confirmation; no permission is asked.
  - **Confirmed:** when the user returns, the hint on Add is gone at once, and the button on the Widget screen is hidden. No message from the app.
  - **Cancelled:** nothing changes.
  - **Refused by the launcher:** the button hides for the rest of this visit; the text steps stay.
  - **A widget already placed:** the Widget screen shows no button, only the text steps.

**Edge cases**
- **Reviews done on another device:** reflected right after sync; before that the count may be stale.
- **Time zone change:** fires around the chosen local time in the new zone. The time is per device.
- **Catch-up:** the count shows today's share, not the whole backlog.
- **Phone restarted:** the reminder keeps working without opening the app.
- **App force-stopped** (Android Settings → Force stop): Android cancels the reminder and the day-start widget update until the app is opened again.
- **App unused for a long time, or battery restrictions:** Android may delay background updates. The widget and reminder show the best known count, and opening the app refreshes them.

**Offline.** Fully offline.

### 5.15 Progress

Opened by tapping the Home **Due today** block. It is its own screen titled **"Progress"**; ← and Back return to Home. The reminder and the widget always open Review, never Progress.

**Content**
- **Today:** tiles for cards **reviewed**, cards **still due**, and **new words** introduced (cards of active words only).
  - Once at least one card has been answered today: **Practice today's words**, with the footer **"Doesn't change your schedule."** ([5.6](#56-review)).
- **Vocabulary:** the number of words that are **New**, **Learning**, **Known well**, **Already known** and **Paused**. Tapping a row opens Words with that filter; Back returns to Progress.
- **Activity:** reviews per day, last 30 days.
- **Captured:** words added per week, last 8 weeks.
- **Top sources:** the sources with the most words.
- No XP, levels, streaks or leaderboards.

**Edge cases**
- **Vocabulary becomes empty while Progress is open** (for example the last word was deleted on another device): the "Build your vocabulary" state with **Add a word**. Progress cannot be opened from an empty Home.
- **Reviews on several devices:** combined after sync; before that, each device shows what it knows.
- **Time zones:** each review counts on its day, in the time zone it was given in; days start at 04:00.
- **Deleted words:** they and their reviews disappear from all numbers.

**Offline.** Computed on the device; fully offline.

### 5.16 Export and backup

**Export** (Settings → Data → Export)
- **Choice:**
  - **Backup (JSON)** — "Everything, including review history. Use it to restore.";
  - **Spreadsheet (CSV)** — "One row per word. No review history; can't be restored."
- **Export N words** prepares the file ("Preparing backup…" / "Preparing spreadsheet…", with **Cancel**, which stops and creates no file).
- **When ready, two ways to deliver it:**
  - **Share:** the Android share sheet (send to Drive, email, a messenger, and so on);
  - **Save to device:** the system's "save file" picker, where the user chooses the folder and name. No permission is needed.
  - **Android difference:** iOS has only its share sheet, which already includes Save to Files.
- **File names:** `ToriWords-backup-YYYY-MM-DD.json` and `ToriWords-YYYY-MM-DD.csv`.
- **CSV** has one row per word: text, translations, definitions, first sentence, source, tags, stage and created date. It is readable and lossy; not a backup.
- **JSON** holds the complete vocabulary: all meanings, sentences, sources, tags and the full review history, in the documented, versioned format shared with iOS and with sync.
- **Attribution.** A file that contains Wiktionary-derived text includes the Wiktionary attribution (CC BY-SA); a file without such text does not. The screen says: "Files with dictionary data include the Wiktionary attribution (CC BY-SA)."
- No sync needed.

**Restore** (Settings → Data → **Restore from backup**)
- **Picking.** The user picks a ToriWords JSON file with the system file picker. While it runs, the row shows "Restoring…".
- **Merging.**
  - Words merge with existing ones by the duplicate rules, and review histories combine. Nothing existing is deleted.
  - Words in the file that were deleted on this device, or in the synced data, after the backup was made are not restored (deletion is terminal).
- **Result:** **"Backup restored"** — "Imported 340 words, 12 merged with existing.", plus "3 words were deleted earlier and were not restored." when that applies.
- **Sync and platforms.** With sync on, the result syncs. A file exported on iOS restores on Android, and the other way round.

**Android device backup.** Android's own backup (Google backup and phone-to-phone transfer) also carries the vocabulary to a new phone without any action in the app.
- It is a silent safety net. The app does not promise it and says nothing about it.
- Android stops backing up an app's data above 25 MB without telling the user, so very large vocabularies may not be included.
- Drive sync resumes after such a restore only if the same Google account is on the new phone; otherwise the user turns it on again ([5.8](#58-google-drive-sync)).
- **Android difference.**

**Edge cases**
- **Empty vocabulary:** export is disabled, with "Add words to export them."
- **Very large vocabulary:** export shows progress and can be cancelled.
- **Same backup restored twice:** no duplicates and no doubled history.
- **Backup from a newer app version:**
  - same backup format: restored, and data this version does not understand is kept unchanged;
  - newer backup format: refused with **"Update the app"** — "This backup was made by a newer version of ToriWords. Update the app to restore it. Nothing was changed."
- **Backup from an older version:** restored.
- **Corrupt or foreign file:** **"This is not a ToriWords backup"** — "Choose a .json file exported from ToriWords. Nothing was changed."
- **Deleted words:** not exported.

**Offline.** Fully offline. Choosing a cloud location in the share sheet or the file picker may need the network; that is outside the app.

## 6. Cross-cutting rules

- **Offline.**
  - Adding, capturing, editing, reviewing, practice, Progress, export and restore never need the network.
  - Only turning on sync, sync itself, Delete Drive data and the translation-model download do.
  - No screen ever blocks on the network.
- **No sign-in or sync prompts** anywhere outside Settings → Google Drive sync: not at first launch, not in empty states, not after a reinstall.
- **Localisation.**
  - Every screen exists in English and Russian, including TalkBack labels and actions.
  - The UI language follows the system when it is Russian or English, otherwise English, and can be overridden per app ([5.9](#59-settings-and-about)).
  - Learning content (words, sentences, translations) is never translated by the UI language.
- **Accessibility.**
  - **Display and screen reader.** System font size and display size, TalkBack, and dark theme on every screen.
  - **Every gesture has a non-gesture path:**
    - review swipes ↔ the Forgot / Remembered buttons;
    - Words row swipes ↔ the entry ⋮ menu and TalkBack custom actions;
    - meaning reorder by drag ↔ Move up / Move down;
    - long-press to select ↔ ⋮ → Select.
  - **Edge gestures.** Custom swipes start inside the content, so system Back from the screen edge always works.
  - **Animations off** (system setting):
    - the launch shows the finished mark;
    - the card flip is not animated;
    - the swipe demo is skipped;
    - a graded card still slides off, because it continues the user's drag;
    - the live header still responds, because it follows the user's own tap.
- **System Back.** On every screen Back does what ← does, with these rules:
  - Back first closes an open row tray, sheet, dialog or menu, or cancels a card drag;
  - in Review and practice, Back leaves the session (answers given in Review are kept);
  - in edit mode with unsaved changes, Back asks "Discard changes?";
  - from the Add preview, Back returns to typing; from Add typing, Back leaves Add without a prompt;
  - on the capture sheet, Back dismisses it without saving.
- **Phone-first.** Phone layouts. Tablets, foldables and resizable windows get the same adaptive layout. Rotation, window resizing, folding and language changes never lose input or the review position.
- **Calm.** No streaks, guilt messages or promotional notifications.
- **Privacy.**
  - No analytics, tracking or crash-reporting SDKs, and no ToriWords server.
  - Data leaves the device only:
    - to the user's own Google Drive (when sync is on);
    - through files the user exports;
    - through the translation model download and the translation library's diagnostics to Google (disclosed in About and in the Play Data safety form).
- **Same behaviour across platforms.** Scheduling, duplicates, merging and counts are identical on Android and iOS. Only suggestions and voices may differ.
- **Theme.** The fixed ToriWords palette (green accent) in light and dark, everywhere, including the widget. Wallpaper-based dynamic colour is not used ([ui.md](ui.md)).
