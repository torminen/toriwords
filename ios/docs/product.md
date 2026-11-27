# ToriWords iOS — Product spec

What the iPhone user experiences: features, behaviour rules, edge cases and offline behaviour. The app supports **iOS 18 and later**; a few visuals (Liquid Glass) need iOS 26.

**Canonical.** This file describes the iOS app on `main` (`ios/`). The Android app follows the same behaviour wherever the platform allows; every deliberate Android difference is listed in [android/docs/ios-differences.md](../../android/docs/ios-differences.md). Where the app does not yet do what is planned, the feature says **Not yet implemented** or **Partly implemented** inline.

**Related files:**
- vocabulary model, states and merge rules: [domain.md](domain.md);
- screens, layout, motion and haptics: [ui.md](ui.md);
- English and Russian strings: [copy.md](copy.md);
- how it is built: [architecture.md](architecture.md), [data-model.md](data-model.md), [capture-and-enrichment.md](capture-and-enrichment.md), [scheduler.md](scheduler.md), [sync.md](sync.md).

This file contains no storage schemas, APIs or algorithms.

**Name.** The UI writes the product name as **"ToriWords"**, and that is also the Home Screen label.

**Words used here.** An Entry is a **word** (or phrase). A Sense is a **meaning**. A Context is a **sentence**. Quoted UI strings are the English copy; Russian is in [copy.md](copy.md).

## 1. Goals and principles

**User.** The owner: a native Russian speaker learning English, who meets new words mostly in articles and subtitled series, and finds Anki powerful but inconvenient. Secondary users are other Russian speakers who learn English the same way.

**Goals**
- Be genuinely useful as a daily tool for collecting and reviewing English words and phrases.
- Use the newest stable native technology. When the two goals conflict, usefulness wins.

**Principles**
- **Capture in seconds, from where the word was met,** keeping the sentence and the source. On iOS this is select text → Share → ToriWords in any app.
- **Zero configuration.** Opinionated defaults; no deck or template design; few settings.
- **Local-first.** Everything works offline, with no account. iCloud sync is automatic when the user is signed in to iCloud, and only adds backup and sync between the user's Apple devices.
- **Same behaviour on every platform.** Scheduling, duplicates, merging and counts behave identically on iOS and Android. Only suggestions (machine-translation variants) and voices may differ.
- **Calm.** No streaks, XP, levels, leaderboards, guilt messages or promotional notifications.
- **No lock-in.** The user's data is theirs: CSV and JSON export, an open data format, open source.
- **Privacy.** No analytics, tracking or crash-reporting SDKs, and no ToriWords server. The only exception is iOS's own crash and performance reports, if the user allowed them in iOS Settings.

**Product rules that shape every feature**
- **One language pair: Russian → English.** The model allows more pairs later. The UI has no pair choice.
- **Free sources only.** The bundled Wiktionary dictionary (offline from first launch), and Apple Translation on the iPhone once its English–Russian language data is downloaded.
- **Cards.** Every reviewable word has a recognition card (English → Russian) and a recall card (Russian → English). Words with a captured sentence also get a cloze card.
- **Two grades, Forgot and Remembered.** No Hard or Easy. The scheduler and its intervals are never shown.
- **Daily load.** 10 new words a day by default (0–50; counts words, not cards). There is no cap on due reviews. The review day starts at 04:00. After a break the app spreads the backlog over about a week.
- **Organisation.** Flat tags; one review queue; no decks.
- **Pronunciation.** The iOS text-to-speech voice (US by default, UK as a setting) plus Wiktionary IPA. No recorded audio.
- **Related words.** Up to 8, from bundled dictionary data. The same word gives the same suggestions on iOS and Android. Hidden for words without relations ([5.13](#513-related-words)).
- **Reminders.** One opt-in daily local reminder, only on days with cards, offered after the first finished session. Home Screen and Lock Screen widgets.
- **Progress.** Minimal stats: today, vocabulary by stage, 30-day activity, captures.
- **Deletion.** A confirmation, then a short Undo; the deletion takes effect when the Undo closes. Deletion is terminal and wins over concurrent edits and reviews. There is no trash.
- **Settings scope.** Scheduling settings sync. The reminder, UI language, accent and auto-play are per device.
- **Duplicates.** `ё` equals `е` for duplicates and search. Text is displayed as written.
- **Phone-first.** iPad gets the same adaptive layout.

## 2. Scope

**iOS v1 = the features below.** There are no priority tiers. The few planned pieces that are not built yet are marked inline.

| Feature | Section |
|---|---|
| Add a word by typing (autocomplete, base form, Russian → English lookup, contained phrases, sentence translation help) | [5.1](#51-add-a-word-by-typing) |
| Capture from the share menu (Share Extension) | [5.2](#52-capture-via-share) |
| Duplicates | [5.3](#53-duplicates) |
| Saving without enrichment, auto-fill, Check translation | [5.4](#54-saving-without-enrichment) |
| Phrases as first-class items | [5.5](#55-phrases) |
| Review: recognition, recall and cloze cards; swipe; undo; catch-up; practice | [5.6](#56-review) |
| Words list and entry screen, including bulk actions and suggested meanings | [5.7](#57-words-and-the-entry-screen) |
| iCloud sync | [5.8](#58-icloud-sync) |
| Settings and About | [5.9](#59-settings-and-about) |
| First run, Home, launch animation, live header | [5.10](#510-first-run-home-and-launch) |
| Tags | [5.11](#511-tags) |
| Pronunciation | [5.12](#512-pronunciation) |
| Related words | [5.13](#513-related-words) |
| Daily reminder and widgets | [5.14](#514-reminders-and-widget) |
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
| Reviewing a single tag | One queue in v1. |
| Typed answers, listening and multiple-choice exercises | — |
| App Intents / Shortcuts; review inside the widget; Live Activities; Apple Watch | — |
| iPad-specific layouts (split views) | Same adaptive layout in v1. |
| Saved or synced dismissals of related words | Dismissals last for the current screen only. |
| Push notifications | Reminders are local; other devices update when they sync. |
| iPhone ↔ Android sync | The JSON backup moves words between platforms ([5.16](#516-export-and-backup)). |
| CSV import | Anki import covers migration later. |
| On-device LLM features | Not planned: no Russian support, device-limited, differs per OS. |
| Recorded human audio | Not planned: licences, coverage, size. |
| Streaks, XP, levels, leaderboards | Not planned. |

Planned for v1 but not built yet (marked inline): filtering Words by source ([5.7](#57-words-and-the-entry-screen), [5.11](#511-tags)), tappable Top sources in Progress ([5.15](#515-progress)) and a "Review all now" control during catch-up ([5.6](#56-review)).

## 4. Navigation conventions

- **Navigation stack.** One stack starting at Home; there is no tab bar. Pushed screens have the system **‹ Back** button, and the edge swipe from the left does the same, unless a feature says otherwise. Overflow menus use **•••**.
- **Full-screen covers.** Review and practice open as a full-screen cover with **✕**, so there is no back swipe to compete with card swipes.
- **Sheets.** The capture sheet, the related-word preview, the tag filter and the reminder offer are sheets; swiping one down closes it.
- **Feedback surfaces.** The delete **Undo** is a toast over the current screen. Confirmations are alerts or confirmation dialogs.

Presentation is in [ui.md](ui.md).

## 5. Features

### 5.1 Add a word by typing

**Behaviour**
1. **Opening Add.** Add opens from the **"Add a word…"** field at the top of Home and from **+** in the Words toolbar. It is a pushed screen titled **Add**; the field is focused and the keyboard is up.
2. **Autocomplete.** From the second character, the user's English input shows an autocomplete list of matching words and phrases from the bundled dictionary, each with its part of speech and primary Russian translation.
   - Words already in the vocabulary come first, marked **"In your vocabulary"**. Tapping one opens that entry.
3. **Opening the preview.** Picking a suggestion, or confirming the typed text (the keyboard's return key), opens the **preview**, a screen of its own pushed over typing, with **Save** in its toolbar. It shows:
   - the word with ▶ (pronunciation), IPA and part of speech;
   - **Translation** variants as checkboxes:
     - dictionary variants first, then the Apple Translation result labelled **"Machine translation"**;
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
   - **Widget hint**, after a save, while no ToriWords widget is on the Home Screen and the hint is not snoozed ([5.14](#514-reminders-and-widget)).
8. **First review.** A new word first appears in review within the daily new-word limit ([5.6](#56-review)).
9. **Back.**
   - ‹ Back or the edge swipe from the preview returns to typing with the text kept, without a prompt.
   - ‹ Back or the edge swipe from typing leaves Add at once, without a prompt; typed text is discarded.
10. **Text that looks like a sentence** (more than 6 words, or ending with sentence punctuation; the same rule as capture, [capture-and-enrichment.md](capture-and-enrichment.md)):
    - Typing shows **"Tap the word to save"** with the sentence's words as chips, and **"The text is kept as the sentence."**
    - The user taps one word, or adjacent words for a phrase.
    - **Contained phrases:** the dictionary phrases found in the sentence ("looked after" → "look after") show as chips too. Picking one saves that phrase, with the sentence kept.
11. **Russian typed in the field.** The app offers English candidates for the Russian text from the dictionary. Picking one continues as usual. With no candidates it says **"Type the English word or phrase"**.

**Edge cases**
- **Word already saved.** The preview shows **"Already in your vocabulary"** with **Open word**. Existing meanings show as checked and disabled; new ones can be checked ("Save adds newly checked meanings and the sentence.").
- **Word already saved but marked known or paused.** The preview shows "You marked this as known" or "You paused this word" with "Save adds the sentence and meanings." and a **Resume learning** switch. It applies on Save, and is off by default.
- **Not in the dictionary** (slang, names, new words, many phrases). There is no autocomplete match, and the preview shows the machine translation only.
  - With no machine translation either (the language data is not downloaded, or Apple Translation is not available on this device), the preview says "No suggestions: the word is not in the dictionary, and on-device translation isn't available. Type a translation (optional)." with the translation field. The user types a translation or saves without one ([5.4](#54-saving-without-enrichment)).
- **Several meanings** ("bank"): all dictionary meanings are listed with their part of speech, so the user can pick the one they met.
- **Text with only spaces or punctuation:** Save is disabled.
- **Different suggestions on iOS and Android:** acceptable. What the user saves is what is stored.

**Offline**
- Saving always works.
- Autocomplete, dictionary translations, definitions, IPA, base forms, contained phrases and Russian → English lookup work offline from the first launch, because the dictionary is bundled.
- Machine translation (variants and sentence help) works offline once the English–Russian language data is on the iPhone ([5.9](#59-settings-and-about)).

### 5.2 Capture via Share

**Entry point**
- Select text in any app → **Share** → **ToriWords**, or share text or a link from any app's share menu → **ToriWords**.

This opens a compact **capture sheet** (the share extension) over the current app, so the user stays in the app they were reading. After Save or Cancel the user is back in the source app. Capture never changes the text in the source app.

**Capture sheet**

The exact text rules (word counting, sentence detection and splitting, markup cleanup, length limits, highlight positions) are shared with Android and pinned by `fixtures/capture` ([capture-and-enrichment.md](capture-and-enrichment.md)). What they mean for the user:

1. **Short selection** (up to 6 words, not ending with sentence punctuation). The selection is the word or phrase to save.
   - **From Safari**, the sentence around the selection on the page is filled in automatically, with the word highlighted.
   - From other apps the sentence field (**"Sentence (optional)"**) is empty; the user can paste or type one.
2. **Longer selection** (more than 6 words, or ending with sentence punctuation). The selection is treated as the sentence, and its words show as chips under **"Tap the word to save"**. The user taps one word, or adjacent words for a phrase. The sentence is kept, with the chosen text highlighted.
3. **Save as / Phrases.** For the chosen text, the sheet offers the same dictionary choices as Add:
   - **Save as** the base form (preselected) or the captured form;
   - **contained phrases** as opt-in chips under **"Phrases"**. Picking one saves the phrase instead; the sentence keeps the captured text.
4. **Shared link only** (a URL, no text). The URL (and, from Safari, the page title) becomes the source, and the user types the word. Save is disabled until a word is typed. The entry gets the source but no sentence (a source-only sentence record, [domain.md](domain.md#context)).
5. **Source.**
   - **From Safari:** the page title fills the **Source** field, and the label under it reads "Safari · theguardian.com".
   - **From other apps with a link:** the field shows the domain as its placeholder and the label reads the domain alone ("theguardian.com"). iOS does not tell the extension which other app shared the text.
   - **Without a link:** no source unless the user types a title (**"Source title"**).
   - The last used source title and the last used tags are offered again for 30 minutes.
6. **Translation.**
   - The sheet shows dictionary variants under **"Translation · Wiktionary"**, each with its part of speech and definition, and the IPA. The first variant is preselected, so Save right away keeps it.
   - The sheet shows **no machine translation** and no sentence translation help.
   - **No dictionary match:** "Not in the dictionary", a **"Translation (optional)"** field, and the footer "Without a translation the word is saved as \"Translation pending\"." If the user types nothing, the word is saved **pending enrichment**. The app fills the translation automatically later and flags it **Check translation** ([5.4](#54-saving-without-enrichment)).
7. **Tags.** Collapsed by default (placeholder "work, travel"); the last used tags are offered for 30 minutes.
8. **Save** shows a short **"Saved"** confirmation in the sheet, then closes it and returns to the source app. Target: two taps after the selection for a short selection, once ToriWords is at the front of the share row (ToriWords, then Save).
9. **One-time tip.** On the user's first capture only, the sheet shows **"Tip: put ToriWords first"** — "In the share menu, scroll the app row to More → Edit and drag ToriWords to the top." It is never shown again.

**Edge cases**
- **Word already saved.** "Already in your vocabulary", with up to three existing translations, and "Save adds this sentence and source." ([5.3](#53-duplicates)).
- **Word marked known or paused.** "You marked this as known" / "You paused this word", with a **Resume learning** switch (off by default). Save attaches the sentence; the word resumes only if the switch is on.
- **Selection in Russian or another script.** The sheet says **"ToriWords saves English words and phrases"** and lets the user edit the text. Save stays disabled until the text contains Latin letters.
- **Selection spanning several sentences.** After the user picks the word, only the sentence that contains it is kept.
- **Sentence longer than 500 characters.** Cut to 500 characters around the chosen word, at word boundaries, with "…" marks.
- **Very large share** (more than 5,000 characters). Only the first 5,000 characters are offered for picking. A URL, if present, is still saved as the source.
- **Line breaks, extra spaces, subtitle markup** (`<i>`, `[music]`, a speaker name before a colon): cleaned for display and saving.
- **Inflected form chosen** ("took off"): Save as offers the base form; the highlight marks what was picked.
- **Separable phrasal verbs** ("take your shoes off"): chips pick adjacent words only. The user picks "take" and edits the text to "take off", or picks a contained phrase if the dictionary finds one.
- **App installed but never opened.** Capture works as usual, including dictionary variants: the sheet reads the dictionary from the app. The word is handed to the app and appears in the vocabulary when the app next opens (at once if the app is running); a word without a chosen translation is then filled automatically and flagged Check translation.
- **The sheet cannot reach the app's shared storage** (rare; for example a broken install): Save shows "Could not save. Open ToriWords once, then try again." If the dictionary cannot be read, the no-match line reads "The dictionary is ready after you open ToriWords once".
- **Sheet dismissed** (Cancel or swipe down): nothing is saved.
- **Streaming apps.** Text selection does not work in most video players, so capture from Netflix or YouTube subtitles is not promised. The user types the word instead.
- **Capture while sync is running.** The word is saved locally and syncs afterwards. The sheet never waits for sync.

**Offline.** Capture never needs the network and never waits for it; saving is instant. A pending word shows **"Translation pending"** and is not reviewed until it has a translation.

### 5.3 Duplicates

Identical on iOS and Android. The full rules are in [domain.md](domain.md#normalisation-and-duplicates).

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
- machine translation cannot help: the English–Russian language data is not downloaded, or Apple Translation is not available on this device. Below iOS 26, Apple Translation also works only while the app is open, so background fills wait for the next open.

**Behaviour**
1. The user can **always save**: type a translation, or save with none.
2. A word without a translation carries the **Needs translation** marker and appears under the **Needs translation** filter. It is not reviewed until it has a translation. Its second line says why:
   - **"Translation pending"**: not filled yet. The app is still waiting for a source (the app being opened after a capture, the translation language data).
   - **"No translation found — add your own"**: machine translation ran and returned nothing, repeatedly.
   - **"No translation yet"**: the user cleared the translation or deleted the last meaning. The app does not refill it.
3. **Pending** words are enriched automatically when a source becomes available: when the app opens, when a capture arrives, or after the translation language data is installed.
4. Enrichment **only fills empty fields**. It never replaces what the user typed or edited.
5. **Nothing found.** The entry screen shows the warning **"No translation found — add your own"** ("Not reviewed until it has a translation.") with **Add meaning** and **Try again**. The app also retries by itself when a new source becomes available, for example after the language data is installed, after a dictionary update, or after another device filled it.
6. **Auto-fill of pending captures.** A capture saved without a translation automatically gets the first dictionary variant, or else the machine translation.
   - The word is then flagged **Check translation**: the entry shows the banner **"Check translation" — "Translation added automatically. Check it."**, and the word is listed under the **Check translation** filter until the user opens it or reviews it once.
   - If the app later auto-fills again, the flag is raised again.

**Edge cases**
- **The user typed a translation, and enrichment later finds more.** The typed translation stays the only meaning. Dictionary and machine variants are offered as **Suggested meanings**, never added automatically:
  - on the entry screen, each with **Add**;
  - in the edit form, each with ⊕ ([5.7](#57-words-and-the-entry-screen)).
- **The user deletes an auto-filled translation.** The field stays empty; enrichment never refills a field the user cleared. The word moves to Needs translation with "No translation yet".
- **Enrichment runs on two devices for the same pending word.** One word, one set of meanings.
- **Language data not downloaded, or Apple Translation not available on this device.** The app works with the dictionary only, and Settings → Translation shows the state. Words without a dictionary hit stay "Translation pending" until machine translation becomes available.
- **Many pending words** (for example 30 captures). Enriched in the background without blocking.

**Offline.** Saving is always offline. Enrichment waits and retries silently.

### 5.5 Phrases

- **First-class items.** A phrase (phrasal verb, idiom, collocation, any multi-word expression: "take off", "on the fence", "make ends meet") is saved, listed, searched, reviewed and synced exactly like a single word.
- **Automatic kind.** Word vs phrase is decided automatically: more than one word means a phrase. The user never chooses.
- **Picking a phrase.** In capture or a typed sentence, the user picks a phrase by tapping adjacent word chips, or a **contained phrase** chip.
- **Translation.** Uses the dictionary when it lists the phrase, otherwise machine translation (not in the capture sheet).
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
- Review is a full-screen cover.
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
- **Session header:** **✕**; the position ("2 / 17"; VoiceOver "Card 2 of 17"); **↶** when an answer can be undone; and, on the back, **•••** (Edit, I already know this, Pause, Delete).

**Grading**
- After the flip: **Forgot** and **Remembered**.
- **Swipe** duplicates the buttons, and only after the flip: **right = Remembered**, **left = Forgot**. Before the flip, swiping does nothing.
  - The swipe can start anywhere on the card, including a scrolling back; the first movement decides between moving the card and scrolling.
  - Review is a full-screen cover, so no system back gesture competes with the swipe.
- **Feel.**
  - The card follows the finger and tilts, with "Remembered →" / "← Forgot" labels beside it.
  - Past the grading angle a firm haptic tick says the release will count, and a softer tick says it stopped counting.
  - Released past the angle, the card grades and flies off to its side, keeping the finger's speed; otherwise it springs back.
  - The buttons send the card off the same way. Input is ignored while a card is flying.
  - The next card appears once the previous one has left.
  - Exact values: [ui.md](ui.md).
- **Swipe demo (once).** On the user's first flipped card ever, the card nudges right (Remembered), then left (Forgot), then springs back. It is never shown again (device-local), and is skipped with Reduce Motion.

**Undo last answer**
- **↶** is visible only while there is an answer that can be undone; otherwise it is hidden, not disabled. It undoes only the last answer and brings its card back.
- The last answer stays undoable until the next answer or the end of the session; only then is it saved to the review history, permanently.
- When the app goes to the background or the session is closed, the answer is saved.
- If the app crashes while an answer is still undoable, that one answer is lost.

**Card actions** (•••): **Edit** opens the edit form and returns to the same card; **I already know this**; **Pause**; **Delete** (confirmation, then Undo). These change the word as anywhere else, and its cards leave the session.

**Session**
- **New words** are mixed in among due reviews, up to the daily new-word limit (default 10).
  - The limit counts **words**: a new word uses a slot when its first card is introduced, and its other cards on later days do not use slots.
  - Example: 20 new words waiting, limit 10. Day 1 introduces words 1–10. Day 2 brings their next cards, plus words 11–20.
- **One card per word per day**, at most.
- **Forgot re-show.** A **Forgot** card comes back a few cards later the same day, until it is remembered once. This holds also after closing and reopening the app, and on the user's other devices after sync.
- **Leaving** (✕) at any point keeps every answer given, with no confirmation.
- **Finished screens.** **Done** is the primary button on each of them:
  - **All done for today:** "N cards reviewed · M remembered · K new words" and "Next review: tomorrow" (or "in N days"). Remembered counts cards whose first answer in this session was Remembered.
  - **Nothing to review today:** the title, the next-review line when something is scheduled, and Done.
  - **Learn more new words** (secondary button above Done) appears when new words are waiting and the daily limit is above 0. It adds one more batch of the daily limit, for this session only, and changes no setting. Repeated taps add more batches.
- **Reminder offer.** After the user's first finished session ever, the reminder offer appears over the finished screen ([5.14](#514-reminders-and-widget)).

**Practice today's words**
- **Where.** Opened from **Progress → Today → Practice today's words**. The button, and the footer **"Doesn't change your schedule."**, show only once at least one card has been answered today.
- **Which cards.** Every card answered today, of words that are still active (not paused, marked known or deleted). They are shuffled and shown **once each**: Forgot does not bring a card back.
- **Header:** **"Practice · 2 / 5"**. Cards, flip, swipe, buttons, ↶, ▶ and the ••• actions work as in Review. The ••• actions do change the word.
- **Answers are not stored.** No review history, and no change to due days, stages, today's counts, Home, the widget or the reminder. Nothing syncs.
- **Leaving.** ✕ leaves at once.
- **End:** **"Practice done"**, "N cards · M remembered", **Done**. There is no next-review line, no Learn more new words and no reminder offer.
- **Repeat.** Opening practice again repeats the same set in a new order.

**Daily load and catch-up**
- **Day start.** A review day starts at **04:00 local time**, a constant.
- **Catch-up.** After a break, when the backlog is much larger than the user's normal daily load (computed from recent history), the app enters catch-up:
  - the Due today block on Home shows **"Welcome back — N cards are waiting. We'll spread them over about a week."** under the counts;
  - each day shows a manageable, shrinking share of the backlog, most at-risk cards first;
  - new words pause until catch-up ends.
- **Review all now.** **Not yet implemented.** Planned: a control during catch-up that shows the rest of the backlog in the current session only and stores nothing. Today there is no such control.
- **No cap** on due reviews on a normal day.
- **Same numbers everywhere.** The numbers are defined once in [scheduler.md](scheduler.md), so Home, the widget, the reminder and Android show the same counts.
- **Calm.** No guilt messages, no streaks.

**Edge cases**
- **Word edited mid-review:** the card shows the edit at once; the schedule is unchanged.
- **Word deleted or excluded mid-review:** its cards leave the queue.
- **Same card reviewed on two devices offline:** both answers count, and the due day is recomputed from all answers, identically on iOS and Android.
- **Word deleted on another device while reviewed here:** after sync the word is gone, and the answer given here is dropped (delete wins).
- **Time zone change:** "today" follows the device's current time zone; answers keep the zone they were given in.
- **Device clock wrong:** answers are still recorded.
- **Long sentence or large text size:** the card scrolls, and the word stays highlighted.
- **Word without translation:** no cards ([5.4](#54-saving-without-enrichment)).
- **Thousands of due cards:** catch-up applies.
- **New-word limit 0:** reviews only; new words wait.
- **Nothing added yet** (for example review opened from the widget): **"Add words to start reviewing"** with **Add a word**.

**Offline.** Fully offline: the queue, answers, scheduling and summary. Answers sync later. Due counts on two devices may differ until they sync.

### 5.7 Words and the entry screen

**List** (Words, from the Home toolbar or **All words ›**)
- **Rows and count.** All words, newest first, with a count line ("214 words · newest first", "· A–Z", "· next due first"). Each row shows:
  - the word or phrase;
  - a second line: the primary translation, or the translation state for words without one;
  - a stage marker: **New**, **Learning**, **Known well**, **Known**, **Paused** or **Needs translation**. The rule is in [domain.md](domain.md#entry).
- **Search** ("Search words, translations, sentences"), plus a horizontally scrolling row of filter chips:
  - **All**, **Needs translation**, **Check translation**, **Phrases**, **New**, **Learning**, **Known well**, **Known**, **Paused**, **Tag**.
- **Filter by source** ("all words from this article"). **Not yet implemented.** Planned; where it appears is open.
- **Sort** (toolbar menu): **Newest**, **A–Z**, **Next due**.
- **+** in the toolbar opens Add.
- **Row swipe left:** **I already know this**, **Pause**, **Delete**. Paused and known rows offer **Resume learning** instead of the first two.
  - Only one row is open at a time. Scrolling or tapping elsewhere closes it.
  - The same actions are on the entry's ••• menu, and as VoiceOver actions on the row.

**Search**
- Finds words by English text, Russian translation, definition and sentence text.
- Ignores case and typographic variants; `ё` matches `е`.
- Results update as the user types.
- **No results:** **"No words match '…'"** with **Add '…'**, which opens Add with the text.

**Bulk actions**
- **Entering select mode:** **Select** in the Words ••• menu, or a long-press on a row (its context menu → **Select**).
- **Top bar:** Cancel, "N selected", **Select all** / **Deselect all**.
- **Bottom bar:** **Tag**, **Known**, **Pause**, **Delete**. When every selected word is Known or Paused, **Resume learning** replaces Known and Pause.
- **Tag** adds the chosen tags to the selected words ("Adds tags to N words. Tags they already have stay."). It never removes tags.
- **Delete** asks "Delete N words?" ("They are removed with their review history on all your devices."). The toast "N words deleted" with **Undo** follows; one Undo covers the whole batch.
- Row swipes are off while selecting. Select mode ends after each action. Selected words that leave the list (a filter, search, sync or delete) drop out of the selection.

**Entry screen**
- **Read mode** shows:
  - the word with ▶ and IPA;
  - a **Wiktionary** mark when data came from Wiktionary, linking to the attribution;
  - **Meanings** in order (translation, part of speech, definition). Meanings with the same definition and part of speech show as one row, with their translations comma-separated, each once; a meaning without a definition keeps its own row;
  - **Suggested meanings** (dictionary and machine variants not yet added), each with **Add**;
  - **Sentences**, each with its source; a web source opens the page;
  - **Tags**;
  - **Note**;
  - **Learning:** stage and "Next review: in 3 days" per card direction ("English → Russian", "Russian → English", "Fill in the blank"), with no intervals or scheduler numbers;
  - **Related words** ([5.13](#513-related-words)).
- **Toolbar:** **Edit** and **•••** (**I already know this**, **Pause**, **Delete**; or **Resume learning**, **Delete**).
- **Translation states:**
  - **No translation found:** a warning with **Add meaning** and **Try again**;
  - **Translation pending:** **Add meaning**;
  - **Check translation:** a banner ([5.4](#54-saving-without-enrichment)).
- **Edit mode** (**Edit**) is a Contacts-style form in place, with **Cancel** and **Done**. ‹ Back and the edge swipe are off while editing; edit mode is left only by Cancel or Done. It contains:
  - text and IPA;
  - meanings, each with translation, part of speech and definition. Meanings can be deleted (⊖) and reordered by dragging (≡);
  - **suggested meanings:** the dictionary and machine variants not yet in the form, each with ⊕, between the meanings and **Add meaning**. Machine variants carry the "Machine translation" label. Tapping one adds it as a meaning; it keeps its dictionary origin unless the user edits it. Removing a meaning offers it again;
  - **Add meaning** (a blank row);
  - sentences with sources, and **Add sentence**;
  - tags, note, and **Delete word**.
- **Add meaning from read mode** opens edit mode. It adds a blank row only when there are no suggestions to pick.
- **Unsaved changes:** Cancel asks **"Discard changes?"** (**Keep editing** / **Discard**). With no changes, edit mode closes at once.
- **From Review** (••• → Edit) the entry opens straight in edit mode; Cancel or Done returns to the same card.

**Actions**
- **I already know this:** the word leaves review and stays listed as **Known**. It counts as known in Progress.
- **Pause:** the word leaves review and stays listed as **Paused**.
- **Resume learning:** continues from the existing history.
- **Delete:**
  - confirmation "Delete '<word>'?" — "It is removed with its review history on all your devices.";
  - then the toast "'<word>' deleted" with **Undo**, shown over every screen;
  - the deletion takes effect, and syncs, only when the toast disappears, another delete starts, or the app goes to the background. A crash in that window does not apply it (the word stays);
  - afterwards it cannot be reversed.

**Edge cases**
- **Deleting the last meaning:** allowed; the word moves to Needs translation ("No translation yet").
- **Editing the text of a reviewed word:** history is kept.
- **Deleting the sentence a card uses:** the card uses another sentence, or none.
- **Word deleted on another device while open here:** after sync, **"This word was deleted on another device"**, and the screen closes. Unsaved edits are dropped.
- **Large vocabulary** (10,000+ words): the list and search stay responsive.

**Offline.** Everything works offline; changes sync later.

### 5.8 iCloud sync

The app syncs through the user's **private iCloud** database. There is no ToriWords account, no sign-in and no ToriWords server. iPhone and Android do not sync with each other; the JSON backup moves words between them ([5.16](#516-export-and-backup)). Merge behaviour is identical on both platforms ([domain.md](domain.md#sync-requirements)). Mechanism: [sync.md](sync.md).

**Without iCloud**
- The app is complete without iCloud; all data stays on the device.
- Nothing asks the user to sign in or turn anything on. The empty state, first run and reinstall never mention sync.

**Turning sync on and off**
- Sync is on whenever the user is signed in to iCloud and iCloud is allowed for ToriWords on this iPhone. There is no in-app switch: the iOS per-app iCloud setting decides.
- Settings → iCloud sync explains: "Your words sync through your private iCloud between devices signed in to the same Apple Account. To stop syncing on this device, turn off iCloud for ToriWords in iOS Settings; your words stay on this device." with **Open iOS Settings**.
- When sync becomes available, everything on the device is uploaded and merged with what iCloud already has, then kept in sync in the background. Nothing is asked, and no summary is shown.

**While sync is on**
- **When it syncs:** a few seconds after a local change, when the app comes to the foreground, during background refresh (iOS decides the timing; the app asks for it about every 4 hours), when the network comes back, and when the iCloud account changes. **Sync now** is in Settings → iCloud sync. There is no push: another device picks up changes when it next syncs.
- **Settings root value:** **On**, **Syncing…**, **Waiting for network**, **Off**, **Storage full** or **Deleted**.
- **Status** on the iCloud sync screen:
  - **"Synced <time>"** (relative, for example "Synced 2 min ago");
  - **"Syncing…"**;
  - **"Not synced yet"**;
  - **"Waiting for network"**;
  - **"iCloud is off: words stay on this device"**;
  - **"iCloud storage is full"**;
  - **"Check your device time"** (the device clock is off by more than an hour);
  - **"iCloud data was deleted"**, with **Back up this device again**.
- **Sync now** is disabled when a sync cannot run (for example iCloud off). **Delete iCloud data…** is disabled while iCloud is off or its data was deleted.
- **No choices for the user.** The user is never asked to choose between this device and the cloud. Conflicting edits resolve per field: the most recent change wins, and an automatic fill never beats a user edit. Delete wins over edits.

**Scenarios**

| Scenario | What the user sees |
|---|---|
| iCloud available, local words, iCloud empty | The local vocabulary uploads; status "Synced". |
| iCloud already has words (a second device used offline first, or a reinstall) | Merged automatically. The same words become one word with all meanings, sentences and review history. No question, no summary. |
| Second device, fresh install | The vocabulary downloads by itself. The app is usable during the download. |
| Same word captured, edited or reviewed on two devices offline | One word; the most recent edit wins per field; both answers count. |
| Deleted on one device, edited or reviewed on another | The deletion wins. The deleted word's content is also removed from iCloud. |
| iCloud signed out or turned off for ToriWords | Sync stops; the app keeps working locally; status "iCloud is off: words stay on this device". Changes are kept and upload when iCloud is back. |
| Another Apple Account signs in to iCloud on this iPhone | The words on the device stay and merge into the new iCloud. Nothing is asked. |
| **Delete iCloud data…** (Settings → iCloud sync) | Confirmation "This deletes your words from iCloud. Your other devices keep their copies but stop syncing." The words stay on this iPhone. Needs a connection; offline it says "No internet connection" — "Connect to the internet and try again. Nothing was changed." A failure says "iCloud data was not deleted. Try again later." |
| iCloud data deleted elsewhere (another device, or iOS Settings → iCloud → Manage storage) | This device keeps its words, stops syncing and shows "iCloud data was deleted" with **Back up this device again**, which uploads its words and resumes sync. |
| **Remove all data from this device** (Settings → Data) | With sync on, the warning says the words stay in iCloud and come back at the next sync, and how many unsynced changes would be lost ([5.9](#59-settings-and-about)). |
| iCloud storage full | Status "iCloud storage is full"; the app keeps working; sync resumes when there is space. |
| Words on an Android phone | Not synced with the iPhone. Export a JSON backup on one, and restore it on the other. |

**Edge cases**
- **App updated on one device but not another:** older versions keep syncing; fields they do not know are kept unchanged.
- **Very large first upload:** runs in the background and resumes after interruptions.
- **Device clock wrong:** never loses answers or creates duplicates. An edit from a device whose clock is far behind can lose to an older edit made elsewhere. If the clock is off by more than an hour, the status asks to fix the device time.
- **Builds without iCloud** (personal developer builds): sync is absent and the app works locally.

**Offline.** Everything except sync itself and Delete iCloud data works offline.

### 5.9 Settings and About

Settings are short; the defaults are meant to be right. The review-day start (04:00) and the scheduler parameters (including desired retention) are not shown.

**Root**, a native grouped list in this order: **Learning**, **Reminders** and **Pronunciation** inline, then the drill-in rows **Translation**, **Language**, **iCloud sync**, **Data**, **About**.

| Row | What it does | Default | Scope |
|---|---|---|---|
| New words per day | Drill-in showing the value. Its screen has a stepper "N new words a day", 0–50, with the footer "Counts words, not cards: each new word brings its cards. Applies on all your devices." | 10 | Synced |
| Daily reminder | Switch. While on, a **Time** row shows the time; tapping it opens an inline time wheel ([5.14](#514-reminders-and-widget)). | off, 19:00 | Per device |
| Widget | Drill-in to the **Widget** help screen ([5.14](#514-reminders-and-widget)). | — | — |
| Accent | Drill-in with the value US / UK. Its screen: **US English** / **UK English**, with the footer "Words are spoken with this iPhone's English voice. Applies to this device only." | US | Per device |
| Auto-play on reveal | Switch. | off | Per device |
| Translation | The row value is **"Ready"** when the English–Russian language data is installed, otherwise **"Built-in dictionary"**. | — | Per device |
| Language | The row value is the current app language. | System | Per device (kept by iOS) |
| iCloud sync | The sync screen ([5.8](#58-icloud-sync)); the row value is the short sync status. | — | Per device |
| Data | **Export**; **Restore from backup**; **Tags** (with the tag count); **Remove all data from this device**. | — | — |
| About | Version, source code, licences, attribution, privacy. | — | — |

**Translation screen.** Apple Translation does the machine translation. The screen shows:
- **On-device translation:**
  - **Download** while the language data is available but not on the iPhone. Tapping it shows the system's own download prompt;
  - **Ready** once it is installed;
  - **Not available** when this device does not support Apple Translation.
- **Dictionary (Wiktionary): Bundled**, with the dictionary version.
- A footer that depends on the state:
  - not downloaded: "English → Russian translation runs on this iPhone once its language data is downloaded. Tap Download, or add English and Russian in iOS Settings → Apps → Translate → Downloaded Languages. The dictionary works without it.";
  - not available: "Apple Translation is not available on this device. The built-in dictionary still suggests translations.";
  - ready: "Translations for new words come from the built-in dictionary first, then from Apple Translation on this iPhone."
- The state is re-checked when the user returns from iOS Settings. When the language data becomes installed, words whose enrichment found nothing get another try.
- The status shows only here. Home shows no download indicator. Add shows a reason line only when a word has no suggestions.

**Language**
- The app follows the system language when it is Russian or English, otherwise English.
- It can be overridden for this app only, in the iOS per-app language setting. The Language screen shows **App language** with the current value and **Change in iOS Settings ›**, which opens the app's page in iOS Settings. There is no in-app language picker and the app stores no language choice.
- Changes the interface only ("Changes the interface only. Your words, sentences and translations stay as they are.").

**Data**
- **Export** and **Restore from backup**: [5.16](#516-export-and-backup).
- **Tags**: [5.11](#511-tags).
- **Remove all data from this device.** A red row with a confirmation, "Remove all data from this device?", with **Remove** / **Cancel**:
  - **sync off:** "All your words, review history and tags are deleted from this device. This can't be undone.";
  - **sync on:** "Your words are deleted from this device. They stay in iCloud and come back at the next sync, unless you delete iCloud data in Settings → iCloud sync.", plus "N unsynced changes will be lost." when there are any.

**About**
- **Version** (with the build number), and **Source code** (the GitHub repository).
- **Licences:** dictionary data (Wiktionary, kaikki.org / wiktextract, CC BY-SA 4.0), the open-source libraries, and ToriWords' own licence (Apache 2.0), with a note that the ToriWords name, logo and app icon are not covered by it.
- **Attribution:** "Dictionary data from Wiktionary, CC BY-SA", linking to the licence. Words with Wiktionary data show the **Wiktionary** mark on the entry screen, which links to the attribution.
- **Privacy.** "Your words are stored on this device and, if iCloud is on, in your private iCloud. Nobody else, including us, can read them. No analytics, tracking or crash-reporting SDKs; no usage data is collected. Only the crash and performance reports of iOS itself exist, if you allowed them in iOS Settings."

**Edge cases**
- **System or per-app language changes** in iOS Settings: iOS relaunches the app in the new language.
- **New-word limit lowered** below what was already introduced today: no more new words today; nothing is taken back.
- **Synced settings changed on two devices:** the most recent change wins.
- **Notifications denied:** Reminders shows "Notifications are off for ToriWords" with **Open iOS Settings ›** ([5.14](#514-reminders-and-widget)).

**Offline.** All settings work offline, except downloading translation language data and the iCloud actions.

### 5.10 First run, Home and launch

**Launch**
- The system launch screen shows only the app's background colour. The ToriWords mark then grows in at the centre:
  1. the W (the grass) appears;
  2. the T's stem rises through it;
  3. the branch unfurls from the top of the stem;
  4. the leaf unfolds at its end.
- A short rolling haptic (a roll of soft taps) ends as the leaf opens.
- The animation and the haptic play each time the app starts. Returning to the app while it is still running shows the current screen directly.
- The finished mark holds briefly, even when the data is already ready.
- If the app is still loading after that, a dim band sweeps across the mark until it is ready. Then the mark fades out and Home appears (or the screen a reminder or widget tap asked for).
- **Reduce Motion:** the finished mark fades in, the haptic plays at once, then the same hold and fade.
- No spinner.
- If the data cannot be opened: **"ToriWords could not open its data"** with the reason.
- Timings and the haptic pattern: [ui.md](ui.md).

**Home**
- **Layout.** One Home screen; no tab bar.
  - The toolbar holds the ToriWords mark (32 pt) and name, then **Words** and **Settings** (⚙︎).
  - Below it, the **"Add a word…"** field opens Add.
  - No search on Home (search is in Words); no sync or download indicators.
- **Live header.** Tapping the mark or the name is decorative and navigates nowhere:
  - a gust sways the tree and the grass, with a light haptic tap, and a small wave runs along the letters of "ToriWords";
  - taps add to the swing;
  - every fifth tap the leaf falls, with a soft haptic; the next tap grows a new one;
  - the movement follows only the user's own tap, so it plays even with Reduce Motion;
  - VoiceOver reads the header as "ToriWords".
- **Home with words shows:**
  - the **Due today** block;
  - **Recently added**: the 5 newest words with their second line; a tap opens the word;
  - **All words ›**, which opens Words.
- **Due today block.** The whole block except the Review button is one tap target with "Due today ›" and list-row press feedback.

  | State | Block shows | Tap on the block opens |
  |---|---|---|
  | Due | "12 to review · 5 new" (a zero part is left out: "5 new", "12 to review"); in catch-up also the Welcome back line; the **Review** button | Progress |
  | All done today | "All done for today" and "Next review: tomorrow" / "in N days" | Progress |
  | Nothing due (nothing answered today) | "Next review: tomorrow" / "in N days", or "Nothing to review today" when nothing is scheduled | Progress |
  | Words exist but none is reviewable, and at least one needs a translation | "N words need a translation" (N ≥ 1) | Words, filtered to Needs translation |
  | No words | No block; the empty state instead | — |

  - **VoiceOver.** The block is one button: "Due today, 12 to review · 5 new" (or "All done for today, next review tomorrow", and so on). Its hint is "Opens your progress." ("Opens words that need a translation." in the none-reviewable state). The Review button is separate, with the hint "Starts today's review.".
  - **Every word paused or marked known** (nothing reviewable and nothing needs a translation): the block shows the nothing-due state, "Nothing to review today", or "Next review: …" when something is scheduled, and a tap opens Progress. It never shows "0 words need a translation".

**First launch**
- No sign-in screen, no onboarding carousel, no language-pair choice. The app opens on Home.
- **Empty state:** "Build your vocabulary" — "Words you add come back for review just before you forget them.", followed by:
  - **Type it** — tap "Add a word…" above;
  - **From any app** — select text → Share → ToriWords;
  - "Works offline: the dictionary is built in.";
  - **Add your first word**, which opens Add.
- The same card without the button is the hint under the empty Add field.
- **No sync mention.** The empty state never mentions sync, also after a reinstall; with iCloud on, the words come back by themselves.
- The share-menu tip appears in the capture sheet on the first capture, not on Home ([5.2](#52-capture-via-share)).
- **Dictionary:** bundled, offline from the first launch.
- **Translation language data.** The app never downloads it on its own. The user downloads it from Settings → Translation (**Download**, which shows the system prompt) or in iOS Settings. Until then, the app uses the dictionary only, and pending words are filled once it arrives.
- **Notifications** are not requested at first launch.

**Empty states elsewhere**
- **Review, nothing added yet:** "Add words to start reviewing", with **Add a word**.
- **Review, nothing due:** "Nothing to review today" ([5.6](#56-review)).
- **Search with no results:** offers to add the search text.
- **Progress with an empty vocabulary** (it became empty while Progress was open): the "Build your vocabulary" state with **Add a word**.

**Edge cases**
- **First use is a share capture** (app never opened): see [5.2](#52-capture-via-share).
- **Device language neither English nor Russian:** English UI.

**Offline.** The first run works fully offline; only the translation data download needs the network.

### 5.11 Tags

- **Optional.** A word can have any number of tags, and nothing asks for them.
- **Where tags are added:** on the Add preview, in the capture sheet (collapsed by default), in entry edit mode, and with bulk **Tag**.
  - In Add and edit mode, typing suggests existing tags with their counts, plus **Create tag "…"**. The capture sheet takes comma-separated names, with the recent tags as one-tap suggestions.
- **Sticky tags.** The capture sheet offers the last used tags for 30 minutes, like the source title.
- **Filter.** The **Tag** chip in Words opens **"Filter by tag"**:
  - checkable tags with counts, **Clear**, and **Show N words**;
  - with several tags selected, the filter shows words that have **any** of them;
  - the chip then reads "work" or "work +1".
- **Filter by source.** **Not yet implemented** ([5.7](#57-words-and-the-entry-screen)).
- **Settings → Data → Tags** lists tags alphabetically, with word counts:
  - tap → rename;
  - swipe to delete, which asks first: "Delete tag '<tag>'?" — "It is removed from N words. The words stay.";
  - empty: "No tags yet. Add tags to words in Add or when editing a word."
- **Review** is always one queue.

**Edge cases**
- **Names differing only in case or spaces** ("Work", "work "): the same tag. Punctuation counts ("C#" ≠ "C").
- **Renaming to an existing name:** "'work' already exists" — "Merge '<old>' into '<new>'?", and the two merge after **Merge**.
- **Deleting a tag:** removes it from words; the words stay.
- **Same tag created on two devices offline:** one tag after sync.

**Offline.** Fully offline; tags sync.

### 5.12 Pronunciation

**Behaviour**
- **Where ▶ appears:** on the Add preview, the entry screen, the related-word preview, the recognition front and every card back. It plays the English word or phrase with the iPhone's English text-to-speech voice. The capture sheet has no ▶.
- **Sentences.** A long-press on the word's ▶, or ▶ next to a sentence, plays the sentence.
- **IPA** from Wiktionary shows under the word when available; the user can edit it.
- **Accent:** US English by default; UK English as a per-device setting.
- **Auto-play on reveal:** off by default; when on, the word plays as the card flips.
- **Silent switch.** A tap on ▶ always speaks, even when the Ring/Silent switch is on silent, and lowers other audio while it speaks. Auto-play stays silent while the switch is on silent.
- No recorded audio.

**Voices**
- Enhanced and premium voices for the accent are preferred when the user has downloaded them.
- With only basic-quality voices for the accent (a fresh iPhone), the system's standard voice for the accent is used (for example Samantha for US, Daniel for UK), never a novelty or robotic voice.
- **No voice for the chosen accent:** another English voice is used.
- **No English voice at all:** ▶ looks disabled. Tapping it shows **"No English voice"** — "To hear words, download an English voice in Settings → Accessibility → Spoken Content → Voices → English."
- IPA stays visible either way.

**Edge cases**
- **Voices differ between devices and platforms:** acceptable.
- **Symbols or abbreviations:** read as the system voice reads them.
- **Russian translations:** not spoken.

**Offline.** Works with an installed voice. IPA is stored on the word.

### 5.13 Related words

- **Where they appear.** After saving a word in Add ("Related to '<word>'"), and on every entry screen ("Related words"). Up to 8 related English words and phrases: synonyms, related and derived terms, and common phrases containing the word ("mortgage" → "mortgage rate", "remortgage", "loan").
- **Each row:**
  - the word and its primary Russian translation;
  - **Add** saves it with that translation and normal enrichment, in one tap. The saved word has no sentence; its source is "Suggested from '<word>'";
  - **✕** hides it for this screen only. Nothing is stored or synced; the row is back the next time the screen opens.
- Tapping a row opens a preview sheet with ▶, part of speech, translation, definition, **Add to my words** and **Close**.
- Words already in the vocabulary show **"✓ In vocabulary"** and cannot be added.
- The same word gives the same suggestions on iOS and Android (bundled data).

**Edge cases**
- **No relations known** (common for slang, rare words and phrases): the section is hidden. A dictionary build may also drop relations to fit its size budget ([capture-and-enrichment.md](capture-and-enrichment.md)).
- **All suggestions already saved:** "You have all related words".
- **Quality.** Wiktionary relations are narrower than real topics ("down payment" is not offered for "mortgage"). Accepted.

**Offline.** Fully offline; the lists ship with the app.

### 5.14 Reminders and widget

**Daily reminder**
- **Off by default.**
- **The offer.** After the user's first finished review session, the app offers it once in a sheet:
  - **"Remind you to review every day?"** — "Only on days when cards are due. No streaks.";
  - **Reminder time** (default 19:00, the iOS time picker);
  - **Turn on reminder** / **Not now**.

  Swiping the sheet down counts as **Not now**. The reminder is also in Settings → Reminders.
- **Permission.** Turning the reminder on asks for notification permission at that moment, never at first launch. The app never asks again by itself.
- **Denied, or notifications turned off for the app:** the switch stays on, and Settings → Reminders shows **"Notifications are off for ToriWords"** with **Open iOS Settings ›**.
- **Delivery.** One local notification per day at the chosen time.
- **Content.** The notification reads **"12 to review"**, the same count as Home's Due today, including new words. A day with only new words also gets a reminder. Tapping it opens Review. While the app is open, no banner shows.
- **When it does not appear.** No notification on a day with nothing due, or once everything due today is done. No push server.
- **Planning ahead.** Reminders are planned for the coming week each time the app updates its counts (after reviews, sync, edits and on opening). If the app is not opened for more than a week, reminders stop until it is opened again.

**Widget**
- **Sizes:** Home Screen small and medium, and Lock Screen circular and rectangular.
- **Content:**
  - **"12 to review · 5 new"** (a zero part is left out). The small size splits it onto two lines ("12 to review", "5 new"); the circular Lock Screen size shows the total with "to review"; the rectangular one shows "ToriWords" above the line;
  - the medium size adds **"Tap to start reviewing"**;
  - nothing due today: **"Next review: tomorrow"**, or the date ("Next review: Mon, 30 Nov"); never a time;
  - **"Open ToriWords"** when nothing is scheduled, when no word is reviewable or there are no words, when it was placed before the app was ever opened, or when it has not updated for 7 days.
- Tapping it opens Review (or the app, for "Open ToriWords").
- **Updates.** The count is the same as Home's. It updates after reviewing, after sync, and at each 04:00 day start for the coming week.
- **Colours.** The fixed ToriWords palette (light and dark); the Lock Screen sizes follow the system's tinting.

**Widget hint**
- **On Add, after a save,** while no ToriWords widget is on the Home Screen and the hint is not snoozed, a tip appears:
  - **"Add the ToriWords widget"** — "Today's cards on your Home Screen: touch and hold an empty area, tap Edit → Add Widget, then find ToriWords.";
  - **Not now** hides it for 24 hours. The until-time is device-local.
- **After placing.** Once a ToriWords widget is placed, the hint no longer shows on Add. Removing the widget brings it back after the next save.
- **Settings → Reminders → Widget** opens a screen titled **Widget**, with the same tip and no Not now.
- iOS does not let an app place a widget, so the tip only describes the steps.

**Edge cases**
- **Reviews done on another device:** reflected right after sync; before that the count may be stale.
- **Time zone change:** fires at the chosen local time in the new zone. The time is per device.
- **Catch-up:** the count shows today's share, not the whole backlog.
- **App unused for a long time:** iOS may limit background updates. The widget and reminder show the best known count, and opening the app refreshes them.

**Offline.** Fully offline.

### 5.15 Progress

Opened by tapping the Home **Due today** block. It is a pushed screen titled **"Progress"**; ‹ Back and the edge swipe return to Home. The reminder and the widget always open Review, never Progress.

**Content**
- **Today:** tiles for cards **reviewed**, cards **still due**, and **new words** introduced (cards of active words only).
  - Once at least one card has been answered today: **Practice today's words**, with the footer **"Doesn't change your schedule."** ([5.6](#56-review)).
- **Vocabulary:** the number of words that are **New**, **Learning**, **Known well**, **Already known** and **Paused**. Tapping a row opens Words with that filter; ‹ Back returns to Progress.
- **Activity:** reviews per day, last 30 days.
- **Captured:** words added per week, last 8 weeks.
- **Top sources:** the sources with the most words, with their counts. **Partly implemented:** the list is shown but its rows are not tappable; opening Words filtered by a source waits for the source filter ([5.7](#57-words-and-the-entry-screen)).
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
- **Export N words** prepares the file ("Preparing backup…" / "Preparing spreadsheet…", with a progress indicator and **Cancel**, which stops and creates no file).
- **When ready,** the iOS share sheet opens (Save to Files, AirDrop, Mail, a messenger, and so on).
- **File names:** `ToriWords-backup-YYYY-MM-DD.json` and `ToriWords-YYYY-MM-DD.csv`.
- **CSV** has one row per word: text, translations, definitions, first sentence, source, tags, stage and created date. It is readable and lossy; not a backup.
- **JSON** holds the complete vocabulary: all meanings, sentences, sources, tags and the full review history, in the documented, versioned format shared with Android and with sync.
- **Attribution.** A file that contains Wiktionary-derived text includes the Wiktionary attribution (CC BY-SA); a file without such text does not. The screen says: "Files with dictionary data include the Wiktionary attribution (CC BY-SA)."
- No iCloud needed.

**Restore** (Settings → Data → **Restore from backup**)
- **Picking.** The user picks a ToriWords JSON file with the system file picker. While it runs, the row shows "Restoring…".
- **Merging.**
  - When sync is on, one sync runs first, so words deleted on other devices count as deleted.
  - Words merge with existing ones by the duplicate rules, and review histories combine. Nothing existing is deleted.
  - Words in the file that were deleted on this device, or in iCloud, after the backup was made are not restored (deletion is terminal).
- **Result:** **"Backup restored"** — "Imported 340 words, 12 merged with existing.", plus "3 words were deleted earlier and were not restored." when that applies.
- **Sync and platforms.** With sync on, the result syncs. A file exported on Android restores on iOS, and the other way round; this is the only way to move words between iPhone and Android.

**iPhone backup.** The vocabulary is part of the iPhone's own backup (iCloud Backup or a computer backup), so restoring a phone brings it back without any action in the app. It is a silent safety net; the app says nothing about it.

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
  - Only sync itself, Delete iCloud data and downloading translation language data do.
  - No screen ever blocks on the network.
- **No sign-in or sync prompts** anywhere: not at first launch, not in empty states, not after a reinstall. Sync status lives only in Settings → iCloud sync.
- **Localisation.**
  - Every screen exists in English and Russian, including the share extension, the widgets and VoiceOver labels and hints.
  - The UI language follows the system when it is Russian or English, otherwise English, and can be overridden in the iOS per-app language setting ([5.9](#59-settings-and-about)).
  - Learning content (words, sentences, translations) is never translated by the UI language.
- **Accessibility.**
  - **Display and screen reader.** Dynamic Type, VoiceOver and Dark Mode on every screen. Toolbar and header buttons have at least 44 pt targets.
  - **Every gesture has a non-gesture path:**
    - review swipes ↔ the Forgot / Remembered buttons;
    - Words row swipes ↔ the entry ••• menu and VoiceOver actions;
    - long-press to select ↔ ••• → Select.
  - **Reduce Motion:**
    - the launch shows the finished mark;
    - the card flip is a cross-fade;
    - the swipe demo is skipped;
    - a graded card still slides off, because it continues the user's drag;
    - the live header still responds, because it follows the user's own tap.
- **Back.** ‹ Back and the edge swipe do the same on every pushed screen, with these rules:
  - in entry edit mode both are off; Cancel (which asks "Discard changes?" when there are changes) or Done leaves it;
  - from the Add preview, Back returns to typing; from Add typing, Back leaves Add without a prompt;
  - Review and practice are full-screen covers left with ✕ (answers given in Review are kept);
  - the capture sheet is left with Cancel or a swipe down, without saving.
- **Phone-first.** iPhone layouts. iPad gets the same adaptive layout. Rotation and text-size changes never lose input or the review position.
- **Calm.** No streaks, guilt messages or promotional notifications.
- **Privacy.**
  - No analytics, tracking or crash-reporting SDKs, and no ToriWords server.
  - Data leaves the device only:
    - to the user's private iCloud (when iCloud is on for ToriWords);
    - in the iPhone's own backup;
    - through files the user exports.
  - Apple Translation runs on the device; the words are not sent anywhere for translation.
- **Same behaviour across platforms.** Scheduling, duplicates, merging and counts are identical on iOS and Android. Only suggestions and voices may differ.
- **Theme.** The fixed ToriWords palette (green accent) in light and dark, everywhere, including the widgets. Liquid Glass toolbar buttons on iOS 26 ([ui.md](ui.md)).

## 7. Open questions

- **Filter by source:** where it appears in Words (a chip, a menu, or only from Progress → Top sources) is undecided.
- **Review all now:** whether the planned catch-up control is still wanted, given the app has shipped without it.
- **Undoable answer on a crash:** the app loses the one answer that was still undoable. Whether that is acceptable or the answer should be kept is not confirmed by the owner.
- **Source of non-Safari shares:** iOS does not reveal the sharing app, so such sources show only the domain. The owner has not explicitly confirmed this.
