# Product decisions — confirmed by owner 2026-11-10

Status: **Confirmed**. The owner confirmed PD-1 … PD-19 as recommended on 2026-11-10. Each item is recorded as a `decision` memory. The file keeps its name so existing links stay valid; the alternatives are kept as the record of what was rejected.

Each item has the same shape: **Decision**, **Alternatives** (rejected), **Why**, and analysis refs ([competitive analysis](unc://toriwords/document/1), sections and items such as A1, I2, X4, §11 Q6). G1/G2 are the [project goals](memory://10).

Settled owner inputs are not repeated here. They are listed in [README.md](README.md#confirmed-owner-inputs).

Architecture docs carry their own owner questions (S1–S6, B1–B6, A1–A6 and others). Where they overlap with a PD, the confirmed PD answers them; see [Mapping to architecture questions](#mapping-to-architecture-questions).

| # | Question | Decision (short) |
|---|---|---|
| PD-1 | Card directions and exercise types | Both card directions for every entry: recognition (English shown) and recall (Russian shown) flip cards with the captured sentence; cloze on the captured sentence P1 |
| PD-2 | Grading | Two buttons: "Forgot" / "Remembered" |
| PD-3 | Organisation | Flat tags plus filter by source; no decks; one review queue |
| PD-4 | Daily load and catch-up | 10 new words/day; after a break, cap daily reviews so the backlog spreads over about a week, and pause new words |
| PD-5 | Pronunciation | OS text-to-speech (US accent by default, UK as a setting) + IPA from Wiktionary; no recorded audio |
| PD-6 | Topical suggestions | Bundled related-word lists from Wiktionary, offline, same on both platforms; P1 |
| PD-7 | Reminders and widget | One opt-in daily local reminder, only when cards are due; widget "12 to review · 5 new" P1; no streaks |
| PD-8 | Stats | Minimal: today, vocabulary by stage, 30-day activity; no XP or streaks |
| PD-9 | Sign-out and account deletion | Sign-out keeps local data by default, with an explicit "also remove from this device" option |
| PD-10 | Apple and Google on one account | One sign-in method per account in v1; linking later |
| PD-11 | Export | CSV + JSON export, P1, no account needed |
| PD-12 | Backup for users without an account | JSON export doubles as backup; JSON import (restore) P1 |
| PD-13 | Phone-first | Phone layouts; tablets get the same adaptive layout, not tablet-specific screens |
| PD-14 | Base form at capture | Offer the dictionary form when the selected word is an inflected form; P1 |
| PD-15 | Deletion recovery | Confirmation dialog + short "Undo" after delete; no trash |
| PD-16 | Which settings sync | Scheduling settings (new-word limit, scheduler parameters) sync; reminder time, UI language and accent stay per device |
| PD-17 | Edit on one device vs delete on another | Delete wins |
| PD-18 | `ё` and `е` in Russian text | Treat as equal for duplicates and search |
| PD-19 | Capture-time help | Auto-fill pending captures (flagged "Check translation"); sentence machine translation as context help; Russian → English lookup |

---

## PD-1. Card directions and exercise types

**Decision.**
- v1 (P0): two flip-card directions for every entry. (These are card directions. "RU → EN" elsewhere names the language pair: native Russian, learning English.)
  - **Recognition** (English shown, answer in Russian): the front shows the English word or phrase and the captured sentence with the word highlighted. The back shows the translation(s), definition and IPA.
  - **Recall** (Russian shown, produce the English): the front shows the translation and the sentence with the word blanked. The back shows the English word.
- P1: **cloze** on the captured sentence as a third card type, available only for entries with a captured sentence.
- Later: typed answers, listening (audio-only front), multiple choice.

**Alternatives (rejected).**
- Recognition only: half the reviews, but no practice in producing the English word.
- Typed answers in v1: stronger recall, but slower on a phone and needs strict or fuzzy matching rules (Lingvist's strict matching is a known complaint, I5).
- Cloze as the main card: strong use of context, but entries typed without a sentence have no cloze.

**Why.** Using the captured sentence in review is the payoff of capture-with-context (A2, §6.1). Two directions are the minimum for passive and active vocabulary. Flip cards keep review fast on the phone (I2). §11 Q7.

## PD-2. Grading

**Decision.** Two buttons after the card is flipped: **Forgot** and **Remembered**. Swipe left/right does the same. No Hard/Easy in v1.

**Alternatives (rejected).**
- Anki's four buttons (Again/Hard/Good/Easy): finer data for the scheduler, but the choice is a known source of friction for people who left Anki (§6.4, X6).
- Grade inferred from typed or chosen answers (Lingvist, Clozemaster): no self-assessment, but needs typed or multiple-choice exercises (see PD-1).
- Three buttons (Forgot/Hard/Good): a compromise; still one decision more per card.

**Why.** Fast, unambiguous review (I2, ReWord/DuoCards pattern). FSRS-class schedulers work with two grades (§7), so this does not limit the scheduler choice in [scheduler.md](../architecture/scheduler.md). §11 Q6.

## PD-3. Organisation

**Decision.**
- Flat **tags**: an entry can have any number of tags. Tags are optional and never required to save a word.
- The vocabulary list can be filtered by tag and by **source** (for example all words from one article or series).
- No decks. Review is always **one queue** of everything due. Reviewing only one tag ("study this tag now") is later.

**Alternatives (rejected).**
- Anki-style decks: familiar for Anki users, but the user has to decide where each word goes at capture, and decks split the daily queue (X6).
- No organisation at all: simplest, but the owner cannot find "words from The Bear".
- Automatic tags from the source: could be added on top of tags later.

**Why.** Zero decisions at capture (A1, I2), while still letting the owner find words by topic or source. Tags map cleanly from Anki decks and tags for the future import. §11 (organisation), I2.

## PD-4. Daily load and catch-up

**Decision.**
- At most **10 new words** introduced per day by default, adjustable in settings (0–50). Words beyond the limit wait in a "new" queue; capture is never limited.
- No cap on due reviews on a normal day.
- A review day starts at **04:00 local time**, so a late-night session counts as the same day (Anki convention). This is a fixed constant, not a setting ([scheduler.md](../architecture/scheduler.md) §4).
- **Catch-up after a break:** when the backlog is much larger than the user's normal daily load (computed from recent review history), the app says so plainly ("Welcome back — N cards are waiting; we'll spread them over about a week"), pauses new words, and shows a daily share of the backlog, most at-risk cards first, until it is cleared in about a week. **Review all now** shows the rest in the current session only and stores nothing. No guilt messages.
- All counts are computed from synced review history and the date, so they are the same on all the user's devices after sync. The exact numbers are defined only in [scheduler.md](../architecture/scheduler.md#11-daily-queue-and-catch-up-pd-4).

**Alternatives (rejected).**
- No catch-up handling (Anki): a pile of hundreds of cards after a holiday, the main reason for "backlog anxiety" (I4).
- A hard daily review cap: hides the backlog but lets it grow indefinitely.
- No new-word limit (LingQ): capture-heavy days turn into review overload later (§7).

**Why.** A daily tool that survives real life (I4, G2). Capturing from series can add dozens of words in an evening.

## PD-5. Pronunciation

**Decision.**
- A **speaker button** on the entry and on both sides of a card plays the English word or phrase (and, on long-press, the sentence) with the OS text-to-speech voice. Works offline when an English voice is installed.
- Accent: **US English** by default; a per-device setting switches to UK English ([enrichment.md](../architecture/enrichment.md) Q-E3).
- **IPA** from Wiktionary is shown when available, and the user can edit it.
- Auto-play on card reveal: off by default, a setting.
- No recorded audio in v1.

**Alternatives (rejected).**
- Recorded human audio from Wiktionary/Wikimedia Commons: better quality, but per-file licences, uneven coverage, size or network needed (memory://12).
- No audio in v1: cheapest, but pronunciation matters for words met in series.

**Why.** Free, offline and available on both platforms (§8.4). Voices differ between iOS and Android, which is acceptable for audio. §11 Q8.

## PD-6. Topical suggestions

**Decision.**
- P1. After saving a word, and on its detail screen, show **"Related words"**: up to about 8 words or phrases related to it (synonyms, related and derived terms, common phrases containing it), each with a one-tap "Add".
- The source is **related-word lists derived from Wiktionary**, shipped with the app as the same data on iOS and Android. Works offline and gives identical suggestions on both platforms.
- No online-only suggestions in v1.
- Curated topical sets to browse (A8) are later (P2).

**Alternatives (rejected).**
- Own backend with embeddings or an LLM: richer "topic" relations (mortgage → down payment, refinance), but online only, has a running cost, and output is less predictable (X5).
- On-device embeddings: iOS-only API; Android needs a bundled model; suggestions differ by platform (§8.4, §8.7).
- On-device LLM: unavailable for a Russian device language and device-limited (X8).

**Why.** Requested by the owner (I1, a gap no competitor fills). Offline and parity-safe (§8.7 option c). Wiktionary relations are narrower than true topics, so the owner should judge if they are useful enough. **Owner question:** is online-only acceptable for this feature if a later version wants richer topical suggestions from the backend? §11 Q4.

## PD-7. Reminders and widget

**Decision.**
- **Reminder:** one daily local notification at a time the user picks (default 19:00). Sent only when cards are due, with the count ("12 words to review"). Off until the user turns it on. The app suggests turning it on after the first review session, not at first launch.
- **Widget** (P1): home-screen widget showing "12 to review · 5 new" (due reviews and new words still available today) that opens review. Lock-screen variant where the OS supports it.
- **No streaks**, no "you'll lose your streak" messages, no promotional notifications.
- Everything is computed on the device, works offline, no push server.

**Alternatives (rejected).**
- Streaks as the main motivator (Duolingo): effective for some, but pressure-based (X4).
- Several reminders per day / adaptive timing: more nagging, more settings.
- Reviewing inside the widget: attractive, but extra design work on both platforms (§8.5: P2).

**Why.** Daily habit without gamification (A11, X4, X11). §11 Q11.

## PD-8. Stats

**Decision.** P1. One stats screen:
- **Today:** reviewed / still due, new words introduced.
- **Vocabulary:** number of entries that are new, learning, known well, and "already known".
- **Activity:** last 30 days, reviews per day.
- **Captured:** words added per week, top sources.

No XP, levels, streaks or leaderboards.

**Alternatives (rejected).**
- None in v1: simpler, but the owner loses a sense of progress (I6).
- Anki-level charts (retention, intervals, forecast): power-user detail that adds clutter (X6). Could come later.

**Why.** Light motivation via a "where do I stand" view (I6), without gamification (X4). §11 Q11.

## PD-9. Sign-out and account deletion

**Decision.**
- **Sign-out:** keeps the vocabulary on this device; the app continues local-only. Changes not yet uploaded are mentioned before sign-out.
- **Remove all data from this device:** a separate, explicit action in Settings. It warns about unsynced changes.
- **Signing in to a different account** while words from the previous account are still on the device: the app asks once, "Add these N words to this account" or "Remove them from this device first". This is about two people's data, not a sync conflict, so it does not break "never pick a side" (I7).
- **Account deletion** (required by the App Store when sign-in exists): deletes all cloud data. On the device where it is done, the user chooses again whether to keep the local copy. **Other signed-in devices** are signed out the next time they connect, keep their local data as local-only, and tell the user why.

**Alternatives (rejected).**
- Sign-out always wipes local data: safest on a shared phone, but a mis-tap loses unsynced work.
- Sign-out always keeps data: simplest, but no way to clean a device you are giving away, except deleting the app.
- Account deletion also wipes other devices remotely: thorough, but surprising and destructive.

**Why.** Local-first (memory://8): the device copy belongs to the user; signing out only stops syncing. Same as [auth.md](../architecture/auth.md) A3 and A4.

## PD-10. Apple and Google on one account

**Decision.** In v1, an account has **one** sign-in method: Apple or Google. Signing in with the other provider creates a separate account; the sign-in screen says which method this device used before and suggests using the same method on every device. Explicit linking of both methods to one account (with the two accounts' words merged) is P1. Never link automatically by email. Same as [auth.md](../architecture/auth.md) A5.

**Alternatives (rejected).**
- Linking in settings in v1: needed if the owner uses both an iPhone and an Android phone without Apple sign-in on Android. Sign in with Apple works on Android via the web flow, so a single Apple account already covers both platforms ([auth.md](../architecture/auth.md)).
- Automatic merge by email: unreliable, because Apple can hide the email.

**Why.** Less to build and fewer edge cases; both providers work on both platforms. **Owner question:** which phones and which sign-in will the owner use?

## PD-11. Export

**Decision.** P1. Settings → Export creates a file and opens the share sheet:
- **CSV:** one row per entry (text, translations, definitions, first sentence, source, tags, stage), for spreadsheets and other apps.
- **JSON:** everything, including all senses, contexts, sources and the full review history.

Available without an account and offline.

**Alternatives (rejected).**
- No export in v1: contradicts "no lock-in" (X2, A5).
- Anki package (.apkg) export: useful for Anki users, but larger work; later with Anki import.

**Why.** Open source and no lock-in (memory://12, A5, X2).

## PD-12. Backup for users without an account

**Decision.** P1. The JSON export from PD-11 is also the backup: the user's records in the sync format ([sync.md](../architecture/sync.md) §12). **Import from a Toriwords JSON file** restores it on a new or reinstalled device. Imported entries merge with existing ones by the duplicate rules ([duplicates](features/duplicates.md)); review histories are combined, and restoring the same file twice changes nothing. Words deleted after the backup was made are not restored (deletion is terminal, PD-17).

**Alternatives (rejected).**
- Rely only on OS device backups (iCloud device backup; Android Auto Backup, which silently stops above 25 MB per app): automatic, but not under the app's control and not cross-platform. The app also uses them as a silent safety net in every case ([local-storage.md](../architecture/local-storage.md) §7).
- No backup without an account: simplest; a lost phone loses everything.

**Why.** The owner allowed using the app without an account; such users should still be able to move to a new phone.

## PD-13. Phone-first

**Decision.** v1 is designed for phones. On tablets and foldables the same screens adapt to the width (Android 17 requires resizable layouts, §8.1), but there are no tablet-specific layouts such as split view of list and detail.

**Alternatives (rejected).** Tablet-optimised layouts in v1: more design and testing for a secondary device.

**Why.** Capture and review happen on the phone (I3). **Owner question:** does the owner use a tablet for series (§11 Q13)?

## PD-14. Base form at capture

**Decision.** P1. When the selected or typed word is an inflected form that Wiktionary lists (for example "took" → "take", "mortgages" → "mortgage"), the capture screen offers to save the base form instead, with the original sentence kept. Default: base form. Phrases are not changed.

**Alternatives (rejected).** Always save exactly what was selected: simpler, but "took", "taken" and "take" become three entries.

**Why.** Fewer accidental duplicates (inflection is not ignored by duplicate detection, [domain model](domain-model.md#duplicates)), and review practises the dictionary form. Offline with bundled data.

## PD-15. Deletion recovery

**Decision.** Deleting an entry asks for confirmation, then shows an "Undo" for a few seconds. No trash or recycle bin. The deletion takes effect (and syncs) only when the "Undo" disappears, so undo never has to bring back a deletion that other devices already applied (deletion is terminal, PD-17). If the app is closed during the undo window, the deletion is applied; if the app crashes in that window, the deletion is not applied and the word stays ([sync.md](../architecture/sync.md) §6).

**Alternatives (rejected).** A trash with 30-day recovery: safer, but another screen and state to sync.

**Why.** Deletions are rare and deliberate; export (PD-11) covers bigger accidents.

## PD-16. Which settings sync

**Decision.**
- Synced (they affect scheduling, so they must be equal on all the user's devices): daily new-word limit and the scheduler parameter set, including desired retention. Desired retention is **not shown to the user** in v1 ([scheduler.md](../architecture/scheduler.md) Q-S2). Tags sync as data.
- The review-day start (04:00) is a constant, not a setting. If it ever becomes configurable, it must sync.
- Per device: reminder on/off and time, UI language override, pronunciation accent and auto-play.

**Alternatives (rejected).**
- Sync everything (one reminder time for all devices).
- Sync nothing: breaks "same history → same due date on both platforms" ([domain model](domain-model.md#sync-requirements)) as soon as the two devices have different limits. Not viable.

**Why.** Scheduling must be identical across the user's devices. Reminders and UI preferences belong to the phone the user is holding.

## PD-17. Edit on one device vs delete on another

**Decision (architect and product agree).** Deletion is **terminal**. If an entry is deleted on one device and edited or reviewed on another before they sync, the deletion wins: after sync the entry is gone on both, and the other device's edits and reviews are dropped. Saving the same word again later creates a fresh entry with no history.

**Alternatives (rejected).** Edit wins (the entry comes back with its history): no data loss, but a deleted word reappears, which feels like a bug, and it complicates sync.

**Why.** Predictable and the cheapest safe rule ([sync.md](../architecture/sync.md)). Deletion is a deliberate act and rare in practice for a single user.

## PD-18. `ё` and `е` in Russian text

**Decision.** Treat `ё` and `е` as the same letter when comparing Russian text: Sense translations for duplicates ("ёлка" = "елка") and Russian search. Text is always displayed as the user or the dictionary wrote it.

**Alternatives (rejected).** Keep them distinct: two meanings "ёлка" and "елка" on one entry, and searching "елка" misses "ёлка".

**Why.** Russian text very often omits the dots; the distinction almost never separates two different translations of one English word. Normalisation fixtures: [parity-testing.md](../architecture/parity-testing.md) §4.1 (`ru-yo`).

## PD-19. Capture-time help

**Decision.**
1. **Auto-fill pending captures** (P0). A capture saved without a translation (no dictionary hit in the share sheet, machine translation not available there) gets the first dictionary variant or the machine translation automatically when the app next runs. Such entries are flagged **"Check translation"** until the user opens or reviews them ([capture](features/capture-share-selection.md); [enrichment.md](../architecture/enrichment.md) Q-E1).
2. **Sentence translation as context help** (P1). When a sentence was captured, the add/capture screen also shows the machine translation of the whole sentence ("In this sentence: …"). It is not stored unless the user copies part of it into a translation ([enrichment.md](../architecture/enrichment.md) Q-E2).
3. **Russian → English lookup** (P1). Typing Russian in the add field offers English candidates from the dictionary ("how do I say …") ([dictionary-data.md](../architecture/dictionary-data.md) Q-D3).

**Alternatives (rejected).**
1. Leave pending captures without a translation until the user picks one: no wrong automatic meanings, but every capture needs a second visit before it can be reviewed.
2. No sentence translation: simpler screen, but single-word machine translation is often wrong without context.
3. English-only input: the app just asks for English.

**Why.** Capture must stay at two taps (A1), and RU learners benefit most from context (§6.3). All three use data the app already has, offline.

## Mapping to architecture questions

Each topic was answered once. Architecture questions not listed here are technical and asked separately.

| Architecture question | Answered by | Note |
|---|---|---|
| [sync.md](../architecture/sync.md) S4 (delete wins, final) | PD-17 | Same decision. |
| [sync.md](../architecture/sync.md) S5 (automatic duplicate merge) | — | Follows from the confirmed "never pick a side" principle and [duplicates](features/duplicates.md); technical. |
| [sync.md](../architecture/sync.md) §11 Settings | PD-16 | Same list. |
| [sync.md](../architecture/sync.md) S6 (no server push) | PD-7 | Product consequence: a second device updates when it next syncs; reminders may be stale until then. |
| [auth.md](../architecture/auth.md) A1 (providers) | Owner input 5 | Apple and Google on both platforms. |
| [auth.md](../architecture/auth.md) A3 (sign-out) | PD-9 | Same decision. |
| [auth.md](../architecture/auth.md) A4 (account deletion, other devices) | PD-9 | Same decision. |
| [auth.md](../architecture/auth.md) A5 (cross-provider identity) | PD-10 | Same decision. |
| [backend.md](../architecture/backend.md) B4 / §4.1 (where sync must work) | [README](README.md#owner-answers-to-open-questions) | Owner: sync must work abroad. |
| [scheduler.md](../architecture/scheduler.md) Q-S1 (grading) | PD-2 | |
| [scheduler.md](../architecture/scheduler.md) Q-S2 (desired retention visible) | PD-16 | Hidden in v1. |
| [scheduler.md](../architecture/scheduler.md) §11 siblings | PD-1 | Behaviour in [review](features/review.md). |
| [capture-and-extensions.md](../architecture/capture-and-extensions.md) Q-C1 (6-word threshold) | — | Product spec value in [capture](features/capture-share-selection.md); no owner question. |
| [capture-and-extensions.md](../architecture/capture-and-extensions.md) Q-C2, Q-C3 (widget number, reminders default) | PD-7 | |
| [enrichment.md](../architecture/enrichment.md) Q-E1, Q-E2 | PD-19 | |
| [enrichment.md](../architecture/enrichment.md) Q-E3 (accent) | PD-5 | |
| [dictionary-data.md](../architecture/dictionary-data.md) Q-D3 (reverse lookup, related words) | PD-19, PD-6 | |
| [local-storage.md](../architecture/local-storage.md) Q-L3 (export file) | PD-11, PD-12 | |
| [parity-testing.md](../architecture/parity-testing.md) `ru-yo` | PD-18 | |
