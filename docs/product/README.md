# Toriwords product spec (v1)

Status: **Confirmed** (owner, 2026-11-10). The owner inputs below and all product decisions PD-1 … PD-19 ([proposed-decisions.md](proposed-decisions.md)) are confirmed. The remaining open questions are listed at the end.

Toriwords is a native iOS and Android app for building a personal vocabulary of English words and phrases met in real content (articles, series, video) and mastering them through spaced repetition.

## Documents

| Document | Contents |
|---|---|
| [domain-model.md](domain-model.md) | Concepts (Entry, Sense, Context, Source, Card, ReviewLog, …), fields, states, invariants, duplicates, sync requirements, future Anki mapping |
| [proposed-decisions.md](proposed-decisions.md) | The product decisions PD-1 … PD-19, confirmed by the owner, mapped to the architecture owner questions |
| [features/](features/) | One file per feature: behaviour, edge cases, offline behaviour, priority |
| [`../architecture/`](../architecture/) | How it is built (architect) |

The [competitive analysis](unc://toriwords/document/1) is referenced by item: A = adopt, I = improve on, X = avoid (§10), Q = open question (§11).

## Goals and user

- **User:** the project owner, a native Russian speaker learning English, who meets new words mostly in articles and subtitled series and finds Anki powerful but inconvenient (§6.4). Other Russian speakers learning English with the same workflow are secondary users.
- **Goals** ([memory://10](memory://10)):
  - genuinely useful as a daily tool for collecting and reviewing words and phrases;
  - built with the newest stable native iOS and Android technology. When the two conflict, usefulness wins.
- **Product principles:**
  - **Capture in seconds, from where the word was met,** with the sentence and source kept (A1, A2).
  - **Zero configuration:** opinionated defaults, no deck or template design, few settings (I2, X6).
  - **Local-first:** everything works offline, with no account; the network only adds sync and backup ([memory://8](memory://8), A4, X1).
  - **Same behaviour on iOS and Android:** scheduling, duplicates and sync behave identically. Only suggestions (translation, voice) may differ ([memory://7](memory://7), §8.7).
  - **Calm:** no streak pressure, no guilt after a break (I4, X4).
  - **No lock-in:** the user's data is theirs ([memory://12](memory://12), X2).

## Confirmed owner inputs

1. v1 is the mobile apps only (iOS, Android). Screenshot OCR and a desktop/browser extension are not in v1.
2. Capture: typing with autocomplete and auto-filled translation and definition, **and** Share / text-selection capture from any app (iOS Share Extension, Android text-selection action).
3. Enrichment sources are free only: on-device translation (Apple Translation / ML Kit) and Wiktionary. Different suggestions on iOS and Android are acceptable.
4. One language pair in v1: **RU → EN**, meaning native Russian, learning English ([memory://11](memory://11)). "RU → EN" names the language pair only; card directions are a separate thing (recognition and recall, both for every entry, PD-1). The data model supports several pairs; v1 ships exactly this one, with no pair switching in the UI. App UI in English and Russian; the device language can be anything.
5. No account needed: the app is fully usable locally. Sign in with Apple or Google only for cloud backup and sync.
6. Anki import comes after v1. The data model must allow it.
7. Card and exercise types, grading, organisation, pronunciation, topical suggestions, reminders, stats and the other PDs were proposed by the team and confirmed by the owner as one list on 2026-11-10 ([proposed-decisions.md](proposed-decisions.md)).
8. Crash reports and anonymous analytics are wanted. The mechanism is pending owner confirmation ([observability.md](../architecture/observability.md)).
9. Sync must work abroad.

## v1 scope

Priorities: **P0** = required for v1. **P1** = planned for v1; can slip to the release right after without breaking v1.

| Feature | Priority | Status | Analysis refs |
|---|---|---|---|
| [Add a word by typing](features/add-word.md) | P0 | confirmed (input 2, PD-14, PD-19) | A1, A6, A13, §11 Q1 |
| [Capture via Share / text selection](features/capture-share-selection.md) | P0 | confirmed (input 2) | A1, A2, A9, I3 |
| [Duplicates](features/duplicates.md) | P0 | confirmed | A2, I7 |
| [Saving without enrichment](features/enrichment-unavailable.md) | P0 | confirmed | A4, [memory://8](memory://8) |
| [Phrases as first-class items](features/phrases.md) | P0 | confirmed | A3 |
| [Review](features/review.md) | P0 | confirmed (PD-1, PD-2, PD-4) | A7, I2, I4, I9, §11 Q6–Q7 |
| [Vocabulary management](features/vocabulary-management.md) | P0 | confirmed (PD-15, PD-17) | X2 |
| [Account and sync](features/account-sync.md) | P0 | confirmed (input 5, PD-9, PD-10, PD-17) | A4, A12, I7, X1 |
| [Settings and about](features/settings-about.md) | P0 | confirmed (input 4, PD-16); analytics mechanism pending | X6, [memory://12](memory://12) |
| [First run and empty states](features/first-run.md) | P0 | confirmed | X1, X6 |
| [Organisation (tags)](features/organisation.md) | P1 | confirmed (PD-3) | I2, X6 |
| [Pronunciation](features/pronunciation.md) | P1 | confirmed (PD-5) | §11 Q8 |
| [Related-word suggestions](features/topical-suggestions.md) | P1 | confirmed (PD-6) | I1, A8, §8.7 |
| [Reminders and widget](features/reminders-widget.md) | P1 | confirmed (PD-7) | A11, X4, X11 |
| [Stats](features/stats.md) | P1 | confirmed (PD-8) | I6, X4 |
| [Export and backup](features/export.md) | P1 | confirmed (PD-11, PD-12) | A5, X2 |

Cross-cutting rules that apply to every feature:
- **Offline:** adding, capturing, editing, reviewing, stats and export never need the network. Only sign-in, sync and first download of on-device translation do.
- **No account prompts** outside Settings → Account.
- **Localisation:** every screen exists in English and Russian. Learning content (words, sentences) is never translated by the UI language.
- **Accessibility:** platform text sizes, screen readers and dark mode are supported on every screen.

## Out of v1 / later

| Item | When | Why |
|---|---|---|
| Screenshot / photo OCR capture | Later (owner input 1) | Not in v1; when it returns is not decided. DRM streaming apps block screenshots on Android (A10, §8.3). |
| Desktop / browser extension | Later (owner input 1) | Outside native mobile scope ([memory://7](memory://7), §11 Q3). |
| Anki import (.apkg) and Anki export | After v1 (owner input 6) | Model is ready ([domain-model.md](domain-model.md#future-anki-import-mapping)). |
| Additional language pairs | Later (owner input 4) | Model is ready. |
| In-app reader for pasted articles | Later | §11 Q3. |
| Subtitle file (.srt/.vtt) import | Later | §8.3, P2. |
| On-device LLM features (Foundation Models, Gemini Nano) | Not planned | No Russian support, device-limited, different per OS (X8). |
| Generated example sentences | Later | Trust (X5, I5); the user's own sentence comes first. |
| Example-sentence corpus (e.g. Tatoeba) | Later | §11 Q2. |
| Curated topical word sets | Later | A8, P2. |
| App Intents / Shortcuts / Android app shortcuts | Later | I8, P2. |
| Review inside the widget, Live Activities, watch apps | Later | §8.5, X11. |
| Tablet-specific layouts | Later (PD-13) | Phone-first. |
| Typed answers, listening and multiple-choice exercises | Later (PD-1) | |
| Streaks, XP, leaderboards | Not planned (PD-7, PD-8) | X4. |

## Owner answers to open questions

Answered on 2026-11-10:
1. **Phones and device language (§11 Q12):** the device language can be anything. The app language follows it when it is Russian or English, otherwise English ([settings](features/settings-about.md)). Nothing else depends on the owner's phones.
2. **Where the owner consumes content (§11 Q13):** not relevant now. OCR capture stays Later.
3. **Analytics and crash reports:** the owner wants **crash reports and anonymous analytics**. The mechanism and what is collected are described in [observability.md](../architecture/observability.md) and are pending owner confirmation. The privacy text in [settings & about](features/settings-about.md) follows that.
4. *(See open question 1 below.)*
5. *(Moved to [PD-19](proposed-decisions.md#pd-19-capture-time-help).)*
6. **Where sync must work:** abroad ([backend.md](../architecture/backend.md) §4.1). The app works offline either way.

Decided later: whether the backend is open source ([backend.md](../architecture/backend.md) B6).

## Open questions for the owner

1. **Undo last answer in a review session:** to be decided during design prototyping (design task). It is feasible only before the answer is written: the last answer stays on the device, unrecorded, until the next answer or the end of the session, and undo discards it. Once recorded and synced it cannot be undone, because review history is immutable ([domain-model.md](domain-model.md#reviewlog)).
2. **Analytics mechanism:** pending owner confirmation of [observability.md](../architecture/observability.md).
