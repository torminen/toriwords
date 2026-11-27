# ToriWords Android — Domain model

The platform-agnostic vocabulary model the Android app uses. The model is the same one the iOS app uses: the same concepts, invariants and merge rules, with the same results on both platforms. Only the transport differs (Google Drive on Android, iCloud on iOS), and the two platforms do not sync with each other.

This file says what each concept means to the user and which rules always hold. It does not define storage:
- tables, columns and IDs: [data-model.md](data-model.md);
- the scheduler and the daily queue: [scheduler.md](scheduler.md);
- the sync protocol, clock and merge implementation: [sync.md](sync.md);
- text normalisation and capture rules: [capture-and-enrichment.md](capture-and-enrichment.md).

User-facing behaviour is in [product.md](product.md).

## Overview

**Notation.** "RU → EN" names the **language pair**: native Russian, learning English. It never names a card direction. The card directions are:
- **recognition**: English shown, answer in Russian;
- **recall**: Russian shown, produce the English;
- **cloze**: the English sentence shown with the word blanked.

**Derived** values are computed on each device from other data and are never synced. Android and iOS must compute them identically; the shared fixtures in `spec/fixtures/` pin this.

**Timestamps.** "Created at" and "updated at" exist for display and sorting only. Conflicts between devices are never resolved by device timestamps; ordering uses the sync clock ([sync.md](sync.md)).

**User-facing words.** Entry = **word** (or phrase). Sense = **meaning**. Context = **sentence**.

| Concept | Meaning |
|---|---|
| LanguagePair | What the user learns: native → target language (v1: RU → EN). |
| Entry | One English word or phrase the user is learning. |
| Sense | One meaning of an Entry: a Russian translation, optionally with an English definition. |
| Context | A real sentence where the user met the Entry, or a source-only record. |
| Source | Where a Context came from: a web page, an app, a typed title, or a suggestion. |
| Card | One way of practising an Entry. The scheduler acts on Cards. |
| ReviewLog | An immutable record of one committed answer to one Card. |
| Tag | A user-defined label on Entries. |
| Device | One app installation. There is no user account. |
| Settings | The user's preferences: some synced, some per device. |

**Relationships:**
- A LanguagePair has many Entries.
- An Entry has many Senses, Contexts and Cards, and many-to-many Tags.
- A Context optionally refers to one Source and one Sense.
- A Card has many ReviewLogs.

## LanguagePair

| Field | Meaning |
|---|---|
| id | Stable global identifier. |
| native language | The language of translations; v1: Russian. |
| target language | The language being learned; v1: English. |
| created at | Display timestamp. |

**Invariants**
- **Natural key: native + target.** Two pairs with the same languages are the same pair, including when two devices each created one on first run.
- v1 has exactly one pair, RU → EN, created automatically on first run. The UI cannot create or switch pairs.
- The languages of a pair never change.
- Every Entry belongs to exactly one pair. Nothing in the model assumes Russian or English.
- The UI language is independent of the pair.

## Entry

| Field | Meaning |
|---|---|
| id | Stable global identifier, assigned on the creating device. |
| language pair | Its LanguagePair. |
| text | The word or phrase as saved or edited ("take off", "mortgage"). Displayed as written. |
| match key | **Derived.** The normalised text used to find duplicates (see [Normalisation and duplicates](#normalisation-and-duplicates)). |
| kind | **Derived.** `word` or `phrase`: more than one word makes a phrase. Both behave the same everywhere. |
| pronunciation (IPA) | Optional. From Wiktionary, or typed. |
| note | Optional free text. |
| status | `active` or `excluded`. |
| excluded reason | When excluded: `already known` or `paused`. |
| enrichment status | `pending`, `done` or `unavailable` (see [Enrichment](#enrichment)). |
| needs check | True when the app filled a translation automatically without the user choosing it. Cleared when the user opens the Entry or reviews it once. Raised again if the app auto-fills again. Drives the **Check translation** filter. |
| origin | How it was created: `typed` (Add), `text selection` (the Android text-selection menu), `shared` (the share menu); later `imported`. iOS has no `text selection`, because every capture there comes through Share. |
| import ref | Optional. Reserved for future imports: source collection + source item id. |
| created at / updated at | Display timestamps. |

**States**

```
active ⇄ excluded (already known | paused)
active / excluded → deleted (terminal)
```

- **active:** its Cards are reviewed when due.
- **excluded:** its Cards never appear in review. It stays in the list and in search. History is kept, and resuming continues from it. `already known` counts as known in Progress; `paused` does not.
  - "I already know this" → excluded / already known.
  - "Pause" → excluded / paused.
  - "Resume learning" → active.
- **deleted:** removed everywhere, together with its Senses, Contexts, Cards and ReviewLogs.
  - **Terminal.** It never comes back, even if another device edited or reviewed it offline; those changes are dropped at sync.
  - Saving the same text later creates a fresh Entry with no history.
  - A short Undo comes before the deletion. The deletion takes effect only when the Undo window closes.

**Word stage** (the marker shown in Words, the stage filters and Progress). **Derived**, checked in this order:
1. No Sense with a translation → **Needs translation**.
2. Excluded as already known → **Known**. Excluded as paused → **Paused**.
3. Every Card is `new` (or the Entry has no Cards yet) → **New**.
4. Every Card is `known well` → **Known well**.
5. Otherwise → **Learning**.

**Translation state** of an Entry without a translation (the second line in lists):
- **Translation pending**: enrichment status `pending`.
- **No translation found — add your own**: enrichment status `unavailable`.
- **No translation yet**: the user cleared the translation or deleted the last meaning.

**Invariants**
- `text` is never empty after trimming.
- An Entry is **reviewable** only if it is `active` and has at least one Sense with a non-empty translation. Otherwise it is saved and listed, but has no Cards in review.
- Within one LanguagePair, at most one non-deleted Entry has a given match key.

## Sense

| Field | Meaning |
|---|---|
| id | Stable global identifier. |
| entry | Its Entry. |
| translation | Russian translation ("ипотека"). May hold several comma-separated synonyms, as written. |
| definition | Optional English definition, usually from Wiktionary. |
| part of speech | Optional. |
| position | Order among the Entry's Senses. The first is the primary meaning, used in lists and review. |
| field provenance | For translation, definition and part of speech: who filled the field (`user`, `wiktionary`, `on-device translation`) and whether the user edited it. |

**Invariants**
- At least one of translation and definition is non-empty.
- Only meanings the user chose or typed are stored. Variants the user did not choose are discarded.
- A suggested meaning added in the Edit form keeps its dictionary or machine-translation provenance, unless the user edits it before saving.
- Senses are displayed by position. Equal positions (concurrent inserts on two devices) are ordered by a deterministic tie-break ([sync.md](sync.md)).
- **Display grouping only:** on the entry screen, Senses with the same definition and part of speech show as one row with their translations joined. On card backs, each translation and each definition shows once. Stored Senses are not changed by this.

## Context

| Field | Meaning |
|---|---|
| id | Stable global identifier. |
| entry | Its Entry. |
| sense | Optional: which Sense the sentence illustrates. |
| sentence | The English sentence as captured or typed. Empty only in a source-only Context. |
| highlight | Optional: where the Entry occurs in the sentence (it may be inflected: "took off" for "take off"), so review can highlight or blank it. Stored as an offset and length in UTF-16 code units, identical on both platforms ([capture-and-enrichment.md](capture-and-enrichment.md)). |
| source | Optional Source. |
| captured at | When it was captured. |

**Source-only Context.** A Context with no sentence, kept only to attach a Source to an Entry. Two cases create one:
- a share of a link with no text (the user typed the word);
- a related word added with one tap (source "Suggested from '<word>'").

A source-only Context always has a Source and never has a highlight.

**Invariants**
- A sentence is at most 500 characters. Longer captures are cut around the word.
- An Entry may have any number of Contexts, including none.
- A highlight lies inside the sentence and never splits a character.
- Review and cloze use only Contexts that have a sentence. Recall and cloze use only Contexts that also have a highlight.

## Source

| Field | Meaning |
|---|---|
| id | Stable global identifier. |
| kind | `web page`, `app`, `other` (a typed title) or `suggested`. |
| url | Optional (web pages). |
| title | Optional page title, typed title ("The Bear S2E3"), or for `suggested` the word it was suggested from. |
| app | Optional: the name of the app the text came from, when Android reports it. |

**Android capture sources**
- **Share with a link:** url + title (+ the app name when known). Displayed as "<app> · <domain>" or as the page title.
- **Text selection:** Android delivers no URL with a selected text. The Source is the app name alone (for example "Chrome") when Android reports the calling app. Otherwise there is no Source unless the user types a title.
- **Typed title:** kind `other`.

**Invariants**
- At least one of url, title and app is present.
- A Source with no Contexts is not shown.
- Several Contexts can share one Source.
- A Source with no title is shown by its domain name.

## Card

| Field | Meaning |
|---|---|
| id | Stable global identifier. |
| entry | The Entry it practises. |
| direction | `recognition`, `recall` or `cloze`. |
| created at | Display timestamp. |
| import ref | Optional, for future imports. |
| learning stage | **Derived.** `new` (never reviewed), `learning` or `known well`. The scheduler sets the thresholds ([scheduler.md](scheduler.md)). |
| due | **Derived.** The review day the Card is next due. |
| scheduling state | **Derived.** Whatever the scheduler needs, recomputed from the Card's ReviewLogs. |

Only id, entry, direction, created at and import ref are synced. Cards are created and removed by the app, never by the user.

**Invariants**
- **Natural key: Entry + direction.** Cards created independently for the same Entry and direction are the same Card.
- Every reviewable Entry has a `recognition` and a `recall` Card as soon as it becomes reviewable.
- It also gets a `cloze` Card once it has a Context with a sentence and a highlight.
- Due day and stage are a pure function of the Card's ReviewLogs, the synced scheduling settings and the scheduler. The same history gives the same result on Android and iOS.
- Excluding an Entry keeps its Cards' history. Deleting the Entry deletes its Cards.
- At most one Card of an Entry is shown per review day (except the same-day re-show of a Forgot card).

## ReviewLog

| Field | Meaning |
|---|---|
| id | Stable global identifier. |
| card | The Card answered. |
| reviewed at | A UTC instant plus the device's UTC offset at that moment. The offset is used for "today" in Progress and the daily limits. |
| rating | Grade 1–4. ToriWords' two buttons produce 1 (**Forgot**) or 3 (**Remembered**). Future imports keep 1–4 as they are. Empty only for imported rows that are not answers. |
| answer duration | How long the user took. |
| device | The Device the answer was given on. |
| import fields | Optional, imported logs only: the original kind, rating and interval. Informational; not used for scheduling. |
| review type | **Derived:** `first study`, `review` or `relearning`, found by replaying the Card's merged log. |
| elapsed since previous review | **Derived.** |

**Invariants**
- Never edited after it is written.
- An answer becomes a ReviewLog only when it is **committed**: when the next answer is given, when the session ends, or when the app goes to the background. An undone answer never becomes a ReviewLog. If the app crashes, or is force-stopped while an answer is still undoable, that one answer is lost.
- **Practice answers never become ReviewLogs.** Practice changes no due day, stage or count, and nothing from it syncs.
- A ReviewLog is removed only together with its Card, when the Entry is deleted.
- When two devices review the same Card offline, both ReviewLogs are kept; neither answer is lost (unless the Entry is deleted).

## Tag

| Field | Meaning |
|---|---|
| id | Stable global identifier. |
| name | The display name, as typed. |

**Invariants**
- **Natural key: tag key.** "Work" and "work " are the same tag; "C#" and "C" are not.
- An Entry can have any number of Tags. Membership has the natural key Entry + Tag.
- Deleting a Tag never deletes Entries.
- Tags never split review. There are no decks.

## Device

| Field | Meaning |
|---|---|
| id | Stable identifier of one installation. |
| platform | `android` (or `ios`). |
| display name | For diagnostics. |
| first seen | When the installation first ran. |

A Device exists from first run, whether or not Google Drive sync is on. There is no user and no account. Data created while sync is off merges into the Drive data when sync is turned on, also when the user picks a different Google account.

## Settings

| Setting | Default | Scope |
|---|---|---|
| New words per day (0–50; counts words, not cards) | 10 | **Synced** |
| Scheduler parameters, including desired retention (not shown to the user) | built in | **Synced** |
| Daily reminder on/off and time | off, 19:00 | Per device |
| Pronunciation accent (US / UK) | US | Per device |
| Auto-play on reveal | off | Per device |
| App language override | System | Per device. Kept by Android on Android 13+; kept by the app on Android 12. |

The review day starts at **04:00 local time**. This is a constant, not a setting.

Synced settings changed on two devices: the most recent change wins.

**Device-local state that is not a setting** (never synced):
- the swipe demo was shown;
- the reminder offer was shown;
- the widget hint's **Not now** until-time.

Practice sessions, the Add hint and dismissed related words store nothing.

## Enrichment

Enrichment fills an Entry's empty fields from the bundled Wiktionary dictionary or from on-device machine translation (ML Kit on Android; Apple Translation on iOS). Mechanism: [capture-and-enrichment.md](capture-and-enrichment.md).

- **Fills only empty fields.** It never overwrites a value.
- **User edits win forever.** Enrichment never changes a field the user edited again, even if the user later empties it.
- **Idempotent.** It may run again at any time, on any device. Automatic enrichment of the same Entry on two devices produces the same meanings, not duplicates. If an enriched value was lost in a sync conflict with a user edit of another field, a later run refills the empty, non-user-edited fields.
- **Status:**
  - `pending`: not enriched yet; retried automatically.
  - `done`.
  - `unavailable`: no source on this device produced a value. The user is told and can type a translation. It is retried when a new source becomes available on any device. On a phone where machine translation can never be available (no Google Play services), an Entry with no dictionary hit goes straight to `unavailable` instead of staying `pending`.
- Enriched values are stored on the Entry and synced. Suggestions may differ between Android and iOS. This affects only what is offered at capture, never stored data or later behaviour.
- Wiktionary-derived data keeps its provenance, which drives the CC BY-SA attribution.

## Normalisation and duplicates

The same item can be created more than once:
- on two devices offline;
- before and after sync was turned on;
- by a repeat capture;
- by a restore.

**Same natural key ⇒ same item.** The items merge, and the user never sees two.

| Concept | Natural key |
|---|---|
| LanguagePair | native + target language |
| Entry | LanguagePair + match key |
| Card | Entry + direction |
| Sense | Entry + translation key (the definition, if the translation is empty) |
| Source | URL. Without a URL: title (match-key rules) + app + whether it is `suggested`. |
| Context | Entry + sentence key (empty for a source-only Context) + Source |
| Tag | tag key |
| Entry ↔ Tag membership | Entry + Tag |

**Text keys.** Every key is computed after Unicode NFC normalisation. The exact rules are fixed by the shared fixtures in `spec/fixtures/` ([capture-and-enrichment.md](capture-and-enrichment.md)). Text is always displayed as written; keys are used only for comparison.

1. **Match key** (Entry text, Source title).
   - Ignores: letter case; leading and trailing whitespace and punctuation; repeated inner spaces; typographic variants of apostrophes, quotes and dashes. `ё` = `е`.
   - Does **not** ignore: inflection ("run" ≠ "ran"), spelling variants ("colour" ≠ "color"), or articles that are part of the text ("the Bear").
   - "Mortgage", "mortgage." and " mortgage " are the same. "don't" and "don’t" are the same.
2. **Translation key** (Sense duplicates, Russian search): the same rules as the match key. "ёлка" = "Елка".
3. **Sentence key** (Context duplicates): whitespace collapsed and trimmed, quote and apostrophe styles unified, `ё` = `е`. **Case and punctuation are kept** ("He ran." ≠ "He ran").
4. **Tag key:** case ignored, whitespace collapsed and trimmed, `ё` = `е`. **Punctuation is kept.**

**Rules**
- Keys are derived. A future change of the rules rebuilds them on each device, and may merge Entries that became equal.
- **Repeat capture or repeat add** never creates a second Entry:
  - the new Context attaches to the existing Entry, unless the same sentence from the same Source is already there;
  - a chosen translation becomes a new Sense only if the Entry does not have it;
  - learning progress and schedule are unchanged.
- **Editing** an Entry's text to another Entry's match key offers a merge. Two such Entries cannot coexist.
- Case that matters to the user ("US" and "us") still means one Entry. Both meanings can be added to it.
- A word and a phrase containing it ("take", "take off") are different Entries, with no link between them.
- **Merging:**
  - The survivor is chosen by a fixed, deterministic rule (effectively the earlier-created Entry), never by device or user, so every device gets the same result ([sync.md](sync.md)).
  - The other Entry's Senses, Contexts and Tag memberships move to the survivor and merge by their own keys. Identical meanings appear once, in the survivor's order.
  - **Delete wins** for the merged word as a whole: if any merged Entry was deleted on some device, the merged word is deleted.
  - Tags: the merged word carries a Tag if any merged Entry did. Removing the tag removes it from all of them.
  - ReviewLogs are never rewritten. They are re-attached to the survivor's Card of the same direction, whose derived state is recomputed from the combined log.

## Sync requirements

What any sync must guarantee, at product level. The Android mechanism (Google Drive app data folder) is in [sync.md](sync.md).

1. **Stable global IDs** for every item. They are assigned offline on any device and never change. Items with natural keys may get deterministic IDs.
2. **ReviewLogs are immutable and append-only**, so concurrent reviews merge without conflict.
3. **Deletion is a synced change.** A deleted item never returns from an offline device. A deleted word's content is also removed from the Drive copy.
4. **Concurrent edits resolve per field, without asking the user.**
   - Edits of different fields are all kept.
   - For the same field, the most recent edit wins by the sync clock, not by device time.
   - An automatic fill never beats a user edit.
   - Delete wins over edits and reviews.
5. **Natural-key merge**, as above. The user never picks "this device or the cloud".
6. **Derived data is not synced.** This covers Card stage, due day and scheduling state; Entry match key and kind; ReviewLog review type and elapsed time. "Same history → same due date on Android and iOS" must hold, so scheduling settings sync.
7. **Data created while sync was off** uploads and merges when sync is turned on, without asking.
8. **Out-of-order arrival.** An item that arrives before what it refers to (for example a ReviewLog before its Card) is kept, but hidden from the user and from review until the referenced item arrives. The result is the same as if everything had arrived at once.
9. **Forward compatibility.** A device running an older app version keeps syncing. Fields it does not know are kept unchanged.
10. **One format.** Android and iOS share one data format and one set of merge rules, pinned by the same fixtures (`spec/fixtures/merge`, `spec/fixtures/hlc`, `spec/fixtures/ids`). The JSON backup uses the same format, so a backup made on either platform restores on the other.

## Future import (after v1)

The model must take an Anki import later without changes:

| Anki | ToriWords |
|---|---|
| Note | Entry. The user maps fields: text, translation (Sense), optionally example (Context) and definition. Other fields go to the note. |
| Card | Card. "Front → back" of the mapped fields = recognition; "back → front" = recall; a cloze note = cloze. Unmappable card types are skipped; their notes still import. |
| Review entry | ReviewLog with its timestamp, rating 1–4 (kept one to one) and duration. The original kind, rating and interval are kept as import fields. Manual or rescheduled rows import with an empty rating and are ignored by the scheduler. |
| Deck | Tag with the deck name. |
| Note tags | Tags. |
| Suspended card | The Entry becomes excluded / paused when all its cards are suspended. |

- Re-importing is idempotent through the import ref.
- Fields convert from HTML to plain text, keeping line breaks.
- An imported note whose text matches an existing Entry merges into it, and the histories combine.
