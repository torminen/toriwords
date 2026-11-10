# Toriwords domain model (v1)

Status: **Proposed**. The owner has not yet confirmed the items marked *pending*. The pending decisions are listed in [proposed-decisions.md](proposed-decisions.md).

This document is platform-agnostic. It defines the vocabulary concepts, their fields, states and invariants as the user experiences them. It does not cover storage, sync mechanisms or scheduling algorithms; those are in [`docs/architecture/`](../architecture/). Field names are descriptive, not a schema.

Related decisions: [native apps](memory://7), [local-first with own backend](memory://8), [project goals](memory://10), [primary pair RU → EN](memory://11), [open source](memory://12).

## Overview

```mermaid
erDiagram
  LanguagePair ||--o{ Entry : contains
  Entry ||--o{ Sense : "has meanings"
  Entry ||--o{ Context : "seen in"
  Context }o--o| Source : "comes from"
  Context }o--o| Sense : "illustrates"
  Entry ||--o{ Card : "is practised by"
  Card ||--o{ ReviewLog : "has history"
  Entry }o--o{ Tag : "organised by (pending)"
  User ||--o{ Device : "signs in on"
```

| Concept | One-line meaning |
|---|---|
| LanguagePair | The direction the user learns in: native language → target language. |
| Entry | One word or phrase in the target language that the user is learning. |
| Sense | One meaning of an Entry: a native-language translation, optionally with a target-language definition. |
| Context | A real sentence where the user met the Entry. |
| Source | Where a Context came from: a web page, an app, or a title the user typed. |
| Card | One way of practising an Entry (for example EN → RU recognition). The scheduler acts on Cards. |
| ReviewLog | An immutable record of one answer to one Card. |
| Tag (pending) | A user-defined label used to organise Entries. |
| User / Device | The optional account and the devices that sync it. |

## LanguagePair

| Field | Meaning |
|---|---|
| id | Stable global identifier. |
| native language | Language of translations and the user's own language. v1: Russian. |
| target language | Language being learned. v1: English. |
| created at | When the pair was created. |

**Invariants**
- v1 has exactly one LanguagePair: RU → EN. It is created automatically on first run. The UI does not offer creating or switching pairs.
- The two languages of a pair never change after creation. A different pair is a different LanguagePair.
- Every Entry belongs to exactly one LanguagePair. Nothing in the model assumes RU or EN, so later versions can add pairs without changing existing data.
- The app's UI language (EN or RU) is independent of the LanguagePair.

## Entry

The word or phrase the user is learning. It is the unit the user sees in the vocabulary list.

| Field | Meaning |
|---|---|
| id | Stable global identifier, assigned on the device that creates the Entry. |
| language pair | The LanguagePair it belongs to. |
| text | The word or phrase in the target language, as the user saved or edited it (for example "take off", "mortgage"). |
| match key | The normalised form of `text` used to detect duplicates. Derived, never edited directly. See *Duplicates*. |
| kind | `word` or `phrase`. Derived from `text`: more than one word means `phrase`. Both kinds behave the same everywhere (see [phrases](features/phrases.md)). |
| pronunciation (IPA) | Optional transcription, from Wiktionary or typed by the user. |
| note | Optional free text from the user. |
| status | `active` or `excluded`. See *Entry states*. |
| excluded reason | When `excluded`: `already known` or `paused`. |
| enrichment status | `pending`, `done` or `unavailable`. See *Enrichment*. |
| created at / updated at | Timestamps. |
| origin | How it was created: `typed`, `shared`, `text selection`, or later `imported`. |

**Entry states**

```mermaid
stateDiagram-v2
  [*] --> active: saved
  active --> excluded: "I already know this" / pause
  excluded --> active: "Resume learning"
  active --> deleted: delete
  excluded --> deleted: delete
  deleted --> [*]
```

- **active:** its Cards take part in review when they are due.
- **excluded:** its Cards never appear in review, but the Entry stays in the vocabulary list and in search. The scheduling history is kept. Resuming continues from that history. `already known` counts as known in [stats](features/stats.md). `paused` does not.
- **deleted:** removed for the user everywhere, together with its Senses, Contexts, Cards and ReviewLogs. Deletion must reach other devices (see *Sync requirements*). v1 has no trash and no undo after the confirmation step (see [vocabulary management](features/vocabulary-management.md)).

**Invariants**
- `text` is never empty after trimming.
- An Entry can be reviewed only if it is `active` and has at least one Sense with a non-empty translation. An Entry without a translation (enrichment pending or unavailable and nothing typed) is saved and listed, but it gets no Cards in review until it has a translation.
- Within one LanguagePair, at most one non-deleted Entry has a given match key (see *Duplicates*).

## Sense

One meaning of an Entry. An Entry can have several (for example "bank" = банк / берег). Only the meanings the user chose or typed are stored; variants offered during capture and not chosen are discarded.

| Field | Meaning |
|---|---|
| id | Stable global identifier. |
| entry | The Entry it belongs to. |
| translation | Native-language translation (RU), for example "ипотека". Can hold several comma-separated synonyms as the user wrote them. |
| definition | Optional target-language (EN) definition, usually from Wiktionary. |
| part of speech | Optional, from Wiktionary or the user. |
| order | Position among the Entry's Senses. The first is the primary one shown in review. |
| field provenance | For each of translation, definition and part of speech: who filled it (`user`, `wiktionary`, `on-device translation`) and whether the user has edited it. |

**Invariants**
- A Sense has at least one of translation or definition non-empty.
- The order of an Entry's Senses is a total order without gaps visible to the user.

## Context

A sentence in which the user met the Entry. Contexts are the main memory aid in review (analysis A2).

| Field | Meaning |
|---|---|
| id | Stable global identifier. |
| entry | The Entry it belongs to. |
| sense | Optional: which Sense this sentence illustrates. |
| sentence | The target-language sentence as captured or typed. |
| highlight | Optional position of the Entry's occurrence in the sentence, so review can highlight or blank it. The occurrence may be an inflected form ("took off" for "take off"). |
| source | Optional Source. |
| captured at | When it was captured. |

**Invariants**
- `sentence` is not empty and is at most the length limit defined in [share/selection capture](features/capture-share-selection.md).
- An Entry can have any number of Contexts, including none. Two Contexts of the same Entry with the same sentence text and Source are the same Context; a repeat capture does not add a copy.
- The highlight, if present, points inside the sentence.

## Source

Where a Context came from. Several Contexts can share a Source (many words from one article).

| Field | Meaning |
|---|---|
| id | Stable global identifier. |
| kind | `web page`, `app` or `other`. |
| url | Optional, for web pages. |
| title | Optional page title, or a title the user typed (for example "The Bear S2E3"). |
| app | Optional name of the app the text was shared from, when the OS provides it. |

**Invariants**
- At least one of url, title or app is present.
- Within one user's data, Sources with the same URL are the same Source.
- A Source without Contexts is not shown to the user.

## Card

One way of practising an Entry. Cards are created and removed by the app, not by the user.

| Field | Meaning |
|---|---|
| id | Stable global identifier. |
| entry | The Entry it practises. |
| direction | Which exercise this Card is. Candidates: `recognition` (see EN, recall RU), `recall` (see RU, produce EN), `cloze` (EN sentence with the Entry blanked). The v1 set is *pending* ([PD-1](proposed-decisions.md#pd-1-card-directions-and-exercise-types)). |
| learning stage | User-visible stage: `new` (never reviewed), `learning`, `known well`. The thresholds between stages are defined by the scheduler ([scheduler](../architecture/scheduler.md)). |
| due | When the Card is next due. Produced by the scheduler. |
| scheduling state | Whatever the scheduler needs per Card. Its content, and whether it is stored or recomputed from ReviewLogs, belongs to [scheduler](../architecture/scheduler.md) and [sync](../architecture/sync.md). |

**Invariants**
- For each Entry there is at most one Card per direction.
- A Card exists for every direction in the v1 set as soon as its Entry becomes reviewable. A `cloze` Card (if adopted) also needs at least one Context with a highlight.
- A Card's due date and stage are a pure function of its ReviewLogs and the scheduler. The same history gives the same result on iOS and Android.
- Excluding an Entry does not change its Cards' history. Deleting an Entry deletes its Cards.

## ReviewLog

One answer to one Card. ReviewLogs are the history of learning and the basis for scheduling and stats.

| Field | Meaning |
|---|---|
| id | Stable global identifier. |
| card | The Card that was answered. |
| reviewed at | Moment of the answer, with the device's UTC offset at that moment (needed for "today" in stats and daily limits). |
| rating | The grade in the v1 grading scheme (*pending*, [PD-2](proposed-decisions.md#pd-2-grading)). |
| review type | `first study`, `review`, `relearning`, or `imported`. |
| elapsed since previous review | Time since the Card's previous review; empty for the first one. |
| answer duration | How long the user took to answer. |
| device | The Device the answer was given on. |
| original rating | Only for imported logs: the rating in the source app's scheme (for example Anki 1–4). |

**Invariants**
- A ReviewLog is never edited after it is written.
- ReviewLogs are removed only together with their Card, when the Entry is deleted.
- Two devices that review the same Card offline both keep their ReviewLogs. Neither answer is lost.

## Tag (pending)

The organisation shape is *pending* ([PD-3](proposed-decisions.md#pd-3-organisation)). The recommendation is flat, many-to-many tags with no decks.

| Field | Meaning |
|---|---|
| id | Stable global identifier. |
| name | Display name. |

**Invariants (if adopted)**
- Tag names are unique per user, ignoring case and surrounding whitespace.
- An Entry can have any number of Tags. Deleting a Tag never deletes Entries.
- Tags do not split review: there is one review queue for all active Entries.

## User and Device

| Concept | Fields | Meaning |
|---|---|---|
| User | id; linked sign-in identities (provider `apple` or `google` + provider's account id); created at | Exists only after the person signs in. Without a User the app works fully, with all data on the device ([account & sync](features/account-sync.md)). |
| Device | id; platform (`ios` / `android`); display name; first seen | One installation of the app. It exists from first run, signed in or not. |
| Preferences | daily new-word limit, reminder time, UI language override | Settings ([settings & about](features/settings-about.md)). Which ones sync across devices is *pending* ([PD-16](proposed-decisions.md#pd-16-which-settings-sync)). |

**Invariants**
- Data created before sign-in belongs to the User after sign-in, and is merged with that User's existing data (see *Duplicates*).
- How many identities one User can have (Apple, Google or both) is *pending* ([PD-10](proposed-decisions.md#pd-10-apple-and-google-on-one-account)).

## Duplicates

- **Natural key:** LanguagePair + match key. Two Entries with the same natural key are the same word for the user.
- **Match key:** the normalised `text`. The exact normalisation rules are fixed by shared fixtures in [parity-testing.md](../architecture/parity-testing.md), so that iOS and Android produce identical keys. The product intent:
  - Ignored: letter case, leading and trailing whitespace and punctuation, repeated inner spaces, typographic variants of apostrophes, quotes and dashes ("don't" = "don’t").
  - Not ignored: inflection ("ran" ≠ "run"), spelling variants ("colour" ≠ "color"), articles that are part of the text ("the" in "the Bear").
- **Repeat capture:** saving text whose natural key matches an existing Entry never creates a second Entry. The new Context is attached to the existing Entry, and a new translation becomes a new Sense only if it differs from the existing ones. Details: [duplicates](features/duplicates.md).
- **Editing:** if the user edits an Entry's `text` so that its match key equals another Entry's, the app offers to merge the two. They cannot coexist.
- **Merging** two Entries (from an edit, or from the same word captured on two devices offline):
  - one Entry survives; the other's Senses, Contexts and Tags move to it, with exact duplicates dropped;
  - ReviewLogs of both are kept and belong to the surviving Entry's Card of the same direction;
  - the result is the same whichever device performs the merge.

## Enrichment

Enrichment fills an Entry's empty fields from Wiktionary or on-device translation ([add word](features/add-word.md), [no-enrichment path](features/enrichment-unavailable.md)).

- **Fills only empty fields.** Enrichment never overwrites a field that has a value.
- **User edits win forever.** A field the user has edited is never changed by enrichment again, even if the user later empties it.
- **Status:**
  - `pending`: captured without enrichment yet (for example saved from the share extension or while translation was unavailable); the app retries automatically.
  - `done`: enrichment ran.
  - `unavailable`: nothing was found or the source is unavailable and retries have stopped; the user is told and can type a translation.
- Enriched values are stored on the Entry and synced. Different suggestions on iOS and Android affect only what is offered at capture, never stored data or behaviour afterwards (analysis §8.7).
- Data that comes from Wiktionary keeps its provenance, so the app can show attribution (CC BY-SA, [open source](memory://12)).

## Sync requirements

Requirements only. The mechanism is decided in [sync.md](../architecture/sync.md).

1. **Stable global IDs.** Every LanguagePair, Entry, Sense, Context, Source, Card, ReviewLog, Tag and Device has a globally unique ID assigned at creation on any device, offline. IDs never change.
2. **Immutable ReviewLog.** ReviewLogs are append-only, so concurrent reviews on several devices merge without conflict.
3. **Deletion via tombstone.** A deletion is itself a synced change, so a deleted item does not come back from another device that was offline.
4. **Versioning placeholder.** Concurrent edits of the same item resolve without asking the user, per field or per record. The granularity and clock (for example HLC vs server version) are chosen in [sync.md](../architecture/sync.md).
5. **Duplicate merge.** Two Entries with the same natural key created on different devices merge as described in *Duplicates*. The user never picks "this device or the cloud".
6. **Derived vs stored Card state.** Whether Card scheduling state is stored and synced or recomputed from ReviewLogs is decided in [sync.md](../architecture/sync.md) and [scheduler.md](../architecture/scheduler.md). Either way, the invariant "same history → same due date on both platforms" holds.
7. **Pre-sign-in data.** Everything created while signed out must be uploadable and mergeable on first sign-in without a full re-upload of later changes.

## Future Anki import mapping

Anki import is after v1. The model must be able to receive it without changes:

| Anki | Toriwords |
|---|---|
| Note | Entry. The user maps note fields: which field is the word or phrase (`text`), which is the translation (Sense `translation`), and optionally which is an example (Context `sentence`) and the definition. Other fields go to `note`. |
| Card | Card. A card generated in the "front → back" direction of the mapped fields becomes `recognition`; "back → front" becomes `recall`; a cloze note becomes `cloze` if PD-1 adopts it, otherwise `recognition`. Card types that do not map are not imported, and their notes are still imported as Entries. |
| Revlog entry | ReviewLog with review type `imported`. It keeps the timestamp, rating, Anki review kind (learn / review / relearn / filtered / manual), elapsed time and answer duration. `original rating` keeps Anki's 1–4. |
| Deck | Tag with the deck name (if PD-3 adopts Tags). |
| Note tags | Tags. |
| Suspended card | Entry `excluded` / `paused` when all its cards are suspended. |

- **Rich text:** Anki fields are HTML. Import converts them to plain text, keeps line breaks, and drops formatting. Media (images, audio) is not imported in the first version of import. The user is told how many fields had media.
- **Ratings:** if PD-2 adopts two buttons, Anki "Again" maps to the failing grade and Hard/Good/Easy map to the passing grade; the original value stays in `original rating`. If PD-2 adopts four buttons, the mapping is one to one.
- **Duplicates:** an imported note whose `text` matches an existing Entry merges into it (see *Duplicates*), and review histories are combined.
- How imported history turns into scheduling state is defined in [scheduler.md](../architecture/scheduler.md).
