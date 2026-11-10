# Capture, extensions, widget and reminders

Status: **Proposed**. Pending owner confirmation in step 5. Nothing here is a `decision` yet.

Covers the OS integration points that run outside the main review UI:
- share and text-selection capture (confirmed for v1);
- the due-count widget and local reminders (proposed; product confirms in the feature list).

Screenshot OCR and desktop/browser extensions are **out of v1** (owner decision). Related: [local-storage.md](local-storage.md) §6, [enrichment.md](enrichment.md), [scheduler.md](scheduler.md) §4, analysis §8.3, §8.5, A9, A11, X9.

## 1. Capture surfaces

| Surface | iOS | Android |
|---|---|---|
| Select text in any app | Selection menu → **Share…** → Toriwords (Share Extension). Two taps. | **`ACTION_PROCESS_TEXT`**: "Toriwords" appears directly in every app's selection toolbar. One tap. |
| Share text / URL from any app | Share Extension (`NSExtensionActivationSupportsText`, `…SupportsWebURLWithMaxCount = 1`). | `ACTION_SEND` with `text/plain` (`EXTRA_TEXT`, `EXTRA_SUBJECT`). |
| Safari page | Same Share Extension; with a JavaScript preprocessing file it can also read the page title, URL and **the sentence around the selection** (P1, `nv` on current Safari). | Chrome's selection toolbar → `PROCESS_TEXT` (no URL or surrounding sentence available). |
| In-app typing | Main app. | Main app. |

**The v1 spec must not promise capture from streaming-app subtitles** (X9). Shared or selected subtitle text works when the source app allows selection or sharing.

## 2. Common capture flow (both platforms)

1. Receive text (and URL/title when the OS provides them).
2. **Clean** the text ([capture](../product/features/capture-share-selection.md) edge cases):
   - Remove `<…>` tags and `[…]` / `(…)` annotations made only of letters and spaces (subtitle markup such as `[music]`).
   - Remove a leading speaker label: up to 3 words followed by `:` at the start of a line.
   - Turn line breaks into spaces and collapse whitespace.
   - Keep only the first **5,000** characters for picking.
3. **Classify:** the text is a **sentence source** if it has **more than 6 words** (whitespace-separated tokens after cleaning) **or** ends with `.`, `!`, `?` or `…` (optionally followed by closing quotes or brackets). Otherwise it is a **term**. A sentence source is shown as tappable word chips, and the user taps one word or several adjacent words to choose the term.
   - Text without any Latin letter can't be saved (Save stays disabled; the user can edit the text).
4. **Sentence extraction** (sentence sources only): keep the one sentence that contains the chosen span.
   - Sentence boundaries: `.`, `!`, `?` or `…`, optionally followed by closing quotes or brackets, then whitespace. A line break in the original text also counts.
   - If that sentence is longer than **500** characters, cut it to 500 characters around the chosen span, at word boundaries, and mark the cuts with `…`.
   - The chosen span becomes the highlight (UTF-16 offset and length within the stored sentence).
5. **Dictionary lookup** ([enrichment.md](enrichment.md) §2): show senses and RU variants; the user picks one or more, or edits. **This is available on both platforms, including the iOS Share Extension**, because it reads only the bundled dictionary file (§3).
6. **Save:** creates or merges the Entry by match key (domain *Duplicates*), its Senses, a Context (if a sentence exists) and a Source (if a URL or title exists).
7. Dismiss. Total target: ≤ 2 s from share to saved for a dictionary hit.

Duplicates: if the match key already exists, the sheet says "Already in your vocabulary" and saves the new sentence and source onto the existing Entry ([duplicates](../product/features/duplicates.md)). On iOS the extension checks this against the **vocabulary index file** (§3); the app import re-checks against the DB, so a stale index never creates a duplicate.

The cleaning, word count, classification, sentence boundaries and the 500-character cut are deterministic text rules. They go into the shared fixtures ([parity-testing.md](parity-testing.md)) so both platforms save the same Context for the same shared text.

**Sticky capture fields:** the last used source title and tags are offered again for 30 minutes ([capture](../product/features/capture-share-selection.md), [organisation](../product/features/organisation.md)).
- They are kept in a small local-only file in the App Group (iOS), read and written by both the extension and the app, last writer wins.
- On Android they are kept in DataStore.
- They are not synced.

## 3. iOS Share Extension: inbox pattern

**Constraints:**
- A separate process with a memory limit of ~120 MB (developer-observed, enforced since iOS 17; Apple publishes no number).
- It can be suspended or killed at any time after dismissal.
- It shares only the App Group container with the app.

**Design:**
- The extension UI is SwiftUI, with no MT, no sync, and no access to `user.sqlite` ([local-storage.md](local-storage.md) §6).
- It opens `AppGroup/dictionary.sqlite` read-only and immutable, for lookup and autocomplete. Memory is a few MB with a small SQLite cache.
- **Vocabulary index:** for duplicate detection, the app writes `AppGroup/vocab-index.json` after every change that adds, renames or deletes Entries.
  - Content: `{format, generatedAt, entries: [[matchKey, entryId, primaryTranslation], …]}`, sorted by match key.
  - Size: about 50 bytes per Entry, so ~0.5 MB for 10,000 Entries.
  - It is written atomically (temp file then rename). The extension only reads it.
- On Save it writes **one JSON file** atomically, as `AppGroup/inbox/<captureId>.json`, using the write-to-temp-then-rename pattern.
- It posts a Darwin notification (`com.toriwords.inbox.changed`) so that a running app imports immediately.
- **App side:** on launch, on foreground, and on the Darwin notification, the app imports every inbox file in `captureId` order. Each import runs in one transaction that also records the file in the `inbox_import` table, and the file is deleted only after the transaction commits.
  - Import is idempotent: a crash between commit and delete just re-skips the file.
  - Entries without a chosen translation get `enrichment_status = pending`, and MT then runs in the app ([enrichment.md](enrichment.md) §4).

**Inbox file (v1):**
```json
{
  "format": 1,
  "captureId": "0193…(UUIDv7)",
  "capturedAt": 1762790400000,
  "utcOffsetMin": 180,
  "languagePair": { "native": "ru", "target": "en" },
  "term": "take off",
  "sentence": "The plane took off an hour late.",
  "highlight": { "offset": 10, "length": 8 },
  "source": { "url": "https://…", "title": "…" },
  "chosenSenses": [
    { "translation": "взлетать", "definition": "To leave the ground…", "pos": "verb",
      "provenance": { "kind": "wiktionary", "dictVersion": "2026.11.1", "headwordKey": "take off", "senseOrdinal": 0 } }
  ],
  "origin": "shared"
}
```
- Highlight offset and length are UTF-16 code units, as in the domain model ([local-storage.md](local-storage.md) §8.4).
- An unknown `format` is left in the inbox untouched. That only happens if the app is older than the extension, which can't happen within one installed bundle; the check is defensive.

**Why not let the extension write the DB:** see [local-storage.md](local-storage.md) §6. In short: `0xDEAD10CC` lock kills, no cross-process observation, and migration ownership.

**Alternatives considered:**
- (a) The extension writes the shared SQLite via GRDB `DatabasePool`. Works with care, but risky (see above).
- (b) The extension just opens the main app via a URL. That isn't allowed for Share Extensions and breaks the user's flow.
- (c) **The inbox (recommended).**

## 4. Android: process-text and share activity

- One `CaptureActivity` with a dialog/bottom-sheet theme and intent filters for `android.intent.action.PROCESS_TEXT` (`text/plain`) and `android.intent.action.SEND` (`text/plain`).
- Text comes from `EXTRA_PROCESS_TEXT` (or `EXTRA_TEXT`).
- If `EXTRA_PROCESS_TEXT_READONLY` is false, we still **don't** return replaced text: we only add the word, never edit the source app's text.
- The activity runs in the **app process**, so it uses the normal repositories, the Room DB and ML Kit directly. No inbox is needed, and MT is available at capture when the model is downloaded.
- The capture use case is the same as on iOS. The only difference is that MT can appear immediately, which is acceptable per the owner.
- No source URL comes with `PROCESS_TEXT`. With `SEND`, a URL found in `EXTRA_TEXT` or `EXTRA_SUBJECT` becomes the Source. The calling app's package name, when available via the referrer, becomes `source.app` (best-effort).
- Keep it light: Android 17 tightened memory limits, and the activity must not start sync or heavy work.
- **Excluded from Recents:** `excludeFromRecents = true`, `taskAffinity = ""`, so the user returns to the source app after saving.

## 5. Due-count widget

**Definition of the number:** "Due today" from [scheduler.md](scheduler.md) §11, shown as two parts: **"12 to review · 5 new"** (PD-7).
- `dueReviews` = the reviews taken for today. **In catch-up mode it is today's capped share (the quota), never the whole backlog.**
- `newAvailable` = today's new Cards (0 in catch-up mode), after the sibling rule.
- The same numbers are shown on the home screen, in the widget and in the reminder.
- When nothing is due, the widget shows the **next due day** ("Next: tomorrow"), not a time; scheduling is day-based.

**Snapshot file.** The app writes it after every change: review, capture import, sync apply, settings change, and day rollover while running.
```json
{ "format": 1, "generatedAt": 1762790400000, "utcOffsetMin": 180,
  "days": [ { "day": 20402, "dueReviews": 12, "newAvailable": 5 },
            { "day": 20403, "dueReviews": 19, "newAvailable": 10 } /* … 7 days */ ],
  "nextDueDay": 20402 }
```
- Counts for future days apply the [scheduler.md](scheduler.md) §11 rules to that day, assuming no further reviews. That is correct until the user reviews, and reviewing rewrites the snapshot.
- The widget picks the entry for `today` computed with the current offset. If the snapshot is older than 7 days, it shows "Open Toriwords".

| | iOS (WidgetKit) | Android (Jetpack Glance) |
|---|---|---|
| Families | Small and medium home screen; accessory circular/rectangular on the lock screen. | 2×1 and 2×2 resizable. |
| Data | Reads `AppGroup/widget-snapshot.json`. | Reads the same snapshot from app storage (Glance runs in the app process). |
| Refresh after changes | `WidgetCenter.shared.reloadAllTimelines()` after writing the snapshot. | `GlanceAppWidget.updateAll(context)` after writing. |
| Day rollover (04:00) | A timeline with one entry per day boundary for the next 7 days, built from the snapshot, so no app launch is needed. | A unique periodic `WorkManager` job (~1 h) that re-renders if the day changed. Rollover may lag by up to ~1 h; acceptable. No exact alarms (they need a special permission). |
| Tap | Deep link `toriwords://review`. | `actionStartActivity` to the review screen. |
| Interactive review in the widget | Out of v1 (P2, analysis §8.5). | Out of v1. |

## 6. Reminders: local notifications only

**Rule:** one optional daily reminder at a user-chosen time (product default, e.g. 19:00), sent only if something is due that day. Posted locally on the device.

| | iOS | Android |
|---|---|---|
| Permission | `UNUserNotificationCenter.requestAuthorization`, asked when the user enables reminders, not at first launch. | `POST_NOTIFICATIONS` runtime permission (API 33+), asked the same way. |
| Scheduling | Up to 7 `UNCalendarNotificationTrigger` requests (one per day). The body uses the snapshot count for that day ("12 words to review"). Days with zero due get no request. Rescheduled every time the snapshot is rewritten. | A `WorkManager` one-time job at the reminder time (inexact, ±15 min), re-enqueued daily. The worker computes the count **live from the DB** and posts nothing if it is zero. |
| Staleness | If the user reviewed everything on another device and this device hasn't synced, the count may be too high. Acceptable. A background sync (`BGAppRefreshTask`) rewrites the snapshot and reschedules when it gets the chance. | Same; the background sync worker refreshes the DB before the reminder when possible. |

**Why no server push in v1:**
- Push would need APNs/FCM credentials and a device-token registry on the backend.
- It would do nothing for users without an account.
- Local scheduling already knows the due count offline.
- Cross-device staleness is a small cost.

Push can be added later for "reviewed elsewhere, cancel today's reminder", if wanted.

No streak pressure or nagging copy in reminders (X4, X11). Live Activities and Live Updates are not used.

## 7. Background work (supporting)

| Task | iOS | Android |
|---|---|---|
| Inbox import | App launch / foreground / Darwin notification. | n/a |
| Sync in background (if signed in) | `BGAppRefreshTask`, opportunistic. | Periodic `WorkManager`, network-constrained. |
| After sync applies changes | Replay affected Cards → rewrite snapshot → reload widget → reschedule reminders. | Same. |
| ML Kit model download | n/a | `WorkManager`, unmetered network. |

## 8. Out of v1 (for reference)

- Screenshot OCR (A10).
- Safari Web Extension (Safari's Share-sheet JS preprocessing is the cheaper P1 option).
- App Intents "Add word" / "Start review" and Android app shortcuts (I8, P2). They would reuse the same capture use case and inbox.
- Interactive widget review.
- Watch apps.

## 9. Open questions

- **Q-C1 (product):** the iOS Share Extension shows dictionary variants in the sheet (§3). Raised in the cross-review for the product capture doc.
- Widget number format: **closed**, "12 to review · 5 new" (PD-7).
- **Q-C2 (spike):** Safari JS preprocessing, to capture the surrounding sentence on iOS.
