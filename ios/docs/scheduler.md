# Scheduler, daily queue, review sessions, widget and reminders

How ToriWords decides what to review and when, on iOS. The rules are shared with the Android app and must give **bit-identical due days** for the same history.

**Fixtures win.** The JSON cases in `fixtures/scheduler/` are normative:
- `fsrs-step.json`
- `fsrs-replay.json`
- `day-boundary.json`
- the `queue-*.json` files
- `snapshot.json`

Their case format and tolerances are in `fixtures/README.md`. If this file and a fixture disagree, the fixture is right and this file gets fixed. How the iOS suites run them: [testing.md](testing.md).

Related files:
- [data-model.md](data-model.md): `card` and `review_log` columns, settings.
- [sync.md](sync.md): how logs from other devices arrive.
- [architecture.md](architecture.md): modules, background refresh, App Group files.

All logic in this file lives in the pure-Swift `ToriCore` module (`Scheduler.swift`, `DailyQueue.swift`, `ReviewSession.swift`, `ProgressStats.swift`, `WidgetSnapshot.swift`, `WidgetDisplay.swift`, `ReminderPlan.swift`). Time is always passed in as arguments, and `ToriCore` never reads the system clock or time zone itself.

## Grading

- A card has two answers, available only after it is flipped:
  - **Forgot** = FSRS rating **1** (Again).
  - **Remembered** = FSRS rating **3** (Good).
  - Swipe right = Remembered, swipe left = Forgot.
- `review_log.rating` always stores an FSRS rating from 1 to 4. Ratings 2 and 4 come only from a later Anki import, which keeps each Anki button one to one.
- `rating = NULL` exists only for imported non-answers (manual or rescheduled rows). The scheduler skips these rows.

## Time sources and the day model

### Day number

Days are whole days. There are no minute steps. A day starts at **04:00 local time**, a constant that is not a setting.

```
dayNumber(t_ms, offsetMin) = floorDiv( floorDiv(t_ms, 1000) + offsetMin*60 − 4*3600, 86400 )
```

- Use 64-bit integers and a floor division at both steps (floor toward −∞, also for instants before 1970). Swift's `/` truncates toward zero, so `DayModel.floorDiv` corrects the quotient when the remainder is non-zero and the signs differ.
- The **review day** of a log is `dayNumber(reviewed_at, utc_offset_min)`. It is fixed when the log is written, so replay never depends on the current time zone.
- **Today** is `dayNumber(now, currentOffsetMin)`.
- A card is **due** when `due_day ≤ today`. This one rule is used everywhere: queue, Home, widget, reminders and stats.

### iOS time sources

| Value | Source |
|---|---|
| `now` | `Date()` in milliseconds (`Now.ms` in `AppEnvironment.swift`), passed into `ToriCore` and `ToriStore` calls (tests pass fixed instants). Every stored instant comes from it: `reviewed_at`, `created_at`, `captured_at`. |
| Current offset | `TimeZone.current.secondsFromGMT() / 60` (`Now.utcOffsetMin`). Read at the moment of use and never cached. A log's `utc_offset_min` is the offset at answer time. |
| `answer_ms` | Time from the card being shown to the answer: `now − shownAt`, both wall-clock milliseconds, clamped to 0 … 600 000 ms. **Partly implemented:** it uses the wall clock, not a monotonic clock, so a clock change during a card skews it (the clamp keeps it in range). |

### Clock and time-zone changes

- **Time-zone change:** nothing stored changes, and "today" follows the device zone.
- **Elapsed days** are clamped at 0 or more.
- **Wrong device clock:** `reviewed_at` is stored as given. Replay sorts by `(reviewed_at, id)` and clamps elapsed days, so the results stay deterministic.

## FSRS-6

### Notation

- `w[0..20]`: the parameters.
- `G`: the rating, 1 to 4.
- `S`: stability, in days.
- `D`: difficulty, in [1, 10].
- `t`: elapsed days, an integer of 0 or more.

### Forgetting curve and interval

```
decay  = −w[20]
factor = 0.9^(1/decay) − 1
R(t, S) = (1 + factor · t / S)^decay

I(r, S)  = S / factor · (r^(1/decay) − 1)
interval = clamp( roundHalfUp(I(desiredRetention, S)), 1, 36500 )
roundHalfUp(x) = floor(x + 0.5)
```

### First review of a new card

```
S0(G) = w[G−1]
D0(G) = w[4] − e^(w[5]·(G−1)) + 1            (clamped to [1, 10] when stored)
```

### Later reviews

The card has state `(S, D)` and last review day `L`. It is reviewed on day `T` with rating `G`, and `t = max(0, T − L)`.

**Difficulty**, for all ratings:
```
ΔD   = −w[6] · (G − 3)
D'   = D + ΔD · (10 − D) / 9
D''  = w[7] · D0(4) + (1 − w[7]) · D'        (D0(4) not clamped)
Dnew = clamp(D'', 1, 10)
```

**Stability.** `D` here is the difficulty *before* this review.

- **Same day** (`t = 0`):
  - `SInc = e^(w[17]·(G − 3 + w[18])) · S^(−w[19])`.
  - If `G ≥ 2`: `SInc = max(SInc, 1)`. This same-day floor matches the pinned reference implementation, py-fsrs 6.3.3.
  - `Snew = S · SInc`.
- **Success** (`t ≥ 1`, `G ≥ 2`), with `R = R(t, S)`:
  `Snew = S · ( e^w[8] · (11 − D) · S^(−w[9]) · (e^(w[10]·(1 − R)) − 1) · hardPenalty · easyBonus + 1 )`
  - `hardPenalty = (G == 2) ? w[15] : 1`
  - `easyBonus = (G == 4) ? w[16] : 1`
- **Lapse** (`t ≥ 1`, `G = 1`), with `R = R(t, S)`:
  - `Sf = w[11] · D^(−w[12]) · ((S + 1)^w[13] − 1) · e^(w[14]·(1 − R))`
  - `Snew = min(Sf, S / e^(w[17]·w[18]))`
- `Snew` is clamped to `[0.001, 36500]`.

### Due day after a review on day T

| Case | `due_day` |
|---|---|
| `G = 1` (any card) | `T` (the card joins today's re-show set) |
| New card, first review, `G = 2` (imports only) | `T` (re-show set) |
| Otherwise | `T + fuzz(interval(desiredRetention, Snew), cardId, reps)` |

- `reps` = the 1-based position of this log among the card's rated logs.
- `lapses` = the number of rated logs with `G = 1` after the first log.

### Parameters

```
w = [0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722,
     0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425,
     0.0912, 0.0658, 0.1542]
desiredRetention = 0.90      (not shown in the UI)
maximumInterval  = 36500
```

- `w` and the retention are identical to py-fsrs 6.3.3 (`FSRSParameters.default`).
- Rounding is still `roundHalfUp`, although py-fsrs rounds half to even.
- The parameter set is synced on the `settings` record: `fsrs_w`, `desired_retention`, `params_id`, `scheduler_version`. Changing any of them triggers a full rebuild (see [Replay and rebuild](#replay-and-rebuild)).
- There is no optimiser in the app.

### Deterministic fuzz

Applied only when `interval ≥ 3` after rounding:

```
ranges = [(2.5, 7.0, 0.15), (7.0, 20.0, 0.10), (20.0, ∞, 0.05)]
delta  = 1.0 + Σ factor · max(0, min(interval, end) − start)
lo     = max(2, roundHalfUp(interval − delta))
hi     = min(roundHalfUp(interval + delta), 36500)
u      = seed(cardId, reps)      ∈ [0, 1)
fuzzed = lo + floor(u · (hi − lo + 1))
```

`seed(cardId, reps)`, in Swift (`FSRS.fuzzSeed`):
1. Take CryptoKit `SHA256.hash(data:)` (swift-crypto on Linux) over the 16 raw bytes of the **canonical** card ID, followed by `reps` as a 4-byte big-endian `UInt32`.
2. Read the first 8 digest bytes as a big-endian `UInt64` `x`.
3. Compute `u = Double(x >> 11) / 9007199254740992` (2^53).

### Numerics (iOS)

- Use `Double` (binary64) only, never `Float`.
- `pow` and `exp` come from Foundation, which is the platform C library: Apple's libm on iOS and macOS, glibc on the Linux CI job. These are not guaranteed to round identically to Android's fdlibm in the last bit. The fixtures' `1e-9` relative tolerance on stability and difficulty absorbs this; due days stay exact because the interval is rounded far from the last bit. Both macOS and Linux CI run the fixture suites.
- `roundHalfUp(x) = Int((x + 0.5).rounded(.down))`. Day arithmetic is in 64-bit `Int`/`Int64`.
- No randomness except the seeded fuzz. No wall-clock reads inside the scheduler: today, review days and parameters are passed in.
- Tolerances against the fixtures:
  - stability and difficulty within `1e-9` relative;
  - `due_day`, interval, `reps`, `lapses` and stage exact.

## Replay and rebuild

### What the cache is

The cached scheduler columns on `card` are a pure function of the canonical card's rated logs and the synced parameter set:
- `stability`, `difficulty`
- `last_review_day`, `due_day`
- `reps`, `lapses`
- `stage`, `params_id`

They are never synced.

### Replay

1. Take the logs whose `canonical_card_id` is this card. That includes its own logs and those of cards merged into it.
2. Exclude orphans and logs of deleted Entries.
3. Sort by `(reviewed_at, id)`, with IDs in unsigned byte order.
4. Skip `rating IS NULL`.
5. Fold the FSRS steps from "new" (`FSRS.replay`).
6. Write the cache.

Review type and elapsed days are derived during the fold, never read from storage. `review_log.review_type` is never filled.

### Stage

| Stage | Condition |
|---|---|
| `new` | No rated logs. |
| `known_well` | `stability ≥ 21` and the last rating ≠ 1. |
| `learning` | Everything else. |

**Entry-level stage** (Words list, Progress). It applies to active Entries that have a translation. The full marker order (Known → Paused → Needs translation → stage; `ToriStore/Queries.swift` `stage(_:translation:)`) is in [domain.md](domain.md#entry).

| Entry stage | Condition |
|---|---|
| **New** | None of its live cards has a rated log, or it has no cards. |
| **Known well** | Every live card is `known_well`. |
| **Learning** | Everything else. |

### When replay runs

Replay runs at the end of every `ToriStore.write` transaction (`Tx.finish`), after canonical-ID resolution, duplicate merge and card creation, so the cache is always consistent with the data the transaction committed.

| Event | Replay |
|---|---|
| Committed local answer | One incremental step (`FSRS.step` from the cached state), equal to a full replay by construction. If the new log is not the newest for its card (an earlier `reviewed_at` than a log already stored), the card gets a full replay instead. |
| A pull brings logs for a card | Full replay of that card. |
| A duplicate merge changes a card's canonical card, a restore | Full replay of the affected cards. |
| Change of `fsrs_w`, `desired_retention` or `scheduler_version` (local or pulled) | Full rebuild of every card, inside the write transaction that applied the change, off the main actor (the sync engine applies pulls). Its time target is owned by [architecture.md](architecture.md#14-performance-targets). |

- Resuming an excluded Entry triggers **no** replay. Excluded Entries keep their cache and are simply not queued, so on resume their existing `due_day` applies.

### Which cards exist

Cards exist only for canonical, live, `active` Entries that have a live Sense with a non-empty translation. Entries without a translation never appear in Review, the widget or Home counts. (`StoreReader.queueInput` joins a card only while its Entry has such a Sense.)

## Daily queue

The queue is computed from synced data plus today (`T`) only. Nothing about it is stored. It runs over the canonical cards of live, `active`, reviewable Entries (`DailyQueue.build`).

### Sets

| Set | Definition |
|---|---|
| **Started** card | Has a rated log before day `T`. |
| **New** card | Has no rated log before `T`. |
| `reviewedToday` | Started cards with at least one rated log on `T`. |
| `waiting` | Started cards with `due_day ≤ T` and no rated log on `T`. |
| **New Entry** | An Entry none of whose cards has a rated log before `T`. |
| `introducedToday` | Entries with no rated log before `T` and at least one on `T`. |
| `reshow` | Cards whose **latest** rated log on `T` leaves `due_day = T` (rating 1, or rating 2 on the card's first-ever log). |
| `answeredToday` | Cards with at least one rated log on `T`. It is a set; its list order is not parity-relevant. |

### Normal load and catch-up

```
activeDays          = the last 14 distinct review days before T with ≥ 1 rated log
reviewsInActiveDays = number of (card, day) pairs on those days where the card was Started before that day
normalLoad          = activeDays empty ? 50 : max(50, ceil(reviewsInActiveDays / |activeDays|))

load    = |waiting| + |reviewedToday|
catchUp = load > 2 · normalLoad
quota   = catchUp ? normalLoad + ceil((load − normalLoad) / 3) : ∞
```

Catch-up spreads a backlog over several days. **Not yet implemented:** "Review all now" (open question, see [product.md](product.md#56-review)). `QueueExtensions.reviewAll` exists in `ToriCore` and lifts the quota, but no screen sets it.

### Building today's queue

The queue is built in one walk.

**Sibling filter** (one card per Entry per day): before a candidate is taken or counted, skip it if another card of the same Entry has a rated log on `T` or was already taken earlier in the walk.

1. **Reviews.**
   - Order `waiting` by `R(T − last_review_day, S)` ascending, then `due_day`, then card ID.
   - Take cards that pass the sibling filter until `max(0, quota − |reviewedToday|)` are taken.
2. **New cards.** None during catch-up. Otherwise:
   - Walk the New cards that have **no rated log on `T`**. Order them by Entry `created_at`, then direction (`recognition` < `recall` < `cloze`), then card ID.
   - A card of a New Entry is taken only while `|introducedToday| + newEntriesTaken < new_words_per_day`. Taking it adds 1 to `newEntriesTaken`. These are the new-word slots.
   - A card of an Entry that is not new (a sibling of a started card) is taken without using the limit.
3. **Re-shows.** The `reshow` set, outside the quota and the limit, with no sibling filter.

**Lowering `new_words_per_day` mid-day** takes nothing back.

### Numbers shown

- **Due today** = the cards taken in steps 1 + 2 + 3, shown as "N to review · M new":
  - N = steps 1 + 3;
  - M = step 2.
  - Home, the widget and the reminder all use this number.
- **Catch-up:** `|waiting|` appears as {n} in the welcome-back line inside Due today ("Welcome back — {n} cards are waiting. We'll spread them over about a week.", see [copy.md](copy.md)).
- **Next due**, when nothing is due: the smallest `due_day > T`, shown as a day, never a time: Home and Review show "tomorrow" / "in N days"; the widget shows "tomorrow" / a date.

**Home "Due today" states**, also written to the widget snapshot:

| State | Condition (first match wins) |
|---|---|
| `empty` | No live Entries. |
| `due` | The queue is non-empty. |
| `allDone` | The queue is empty and at least one rated log exists on `T`. |
| `noneReviewable` | Live Entries exist, none has a live card, **and** at least one live Entry needs a translation (no Sense with a translation, see [domain.md](domain.md#entry)). |
| `nothingDue` | Everything else: "Nothing to review today", or the "Next review…" line when a card is scheduled. |

- Example: live Entries exist, none has a live card, and none needs a translation. That is `nothingDue`, not `noneReviewable`. Same on Android; shared fixture `fixtures/scheduler/queue-basic.json` case qb-003.
- In `DailyQueue.build` the `noneReviewable` test is "no active Entry has a card, and some live Entry has no card". Because the store gives an Entry cards only while it has a translated Sense, an Entry without cards is an Entry that needs a translation (or an excluded one without cards). The code tests `noneReviewable` before `due`; the result is the same because `due` needs a card.

### Learn more new words

- A device-local, session-only extension of the current session (`QueueExtensions.extraNewBatches`). Nothing about it is stored or synced.
- Each tap appends one more batch of `new_words_per_day` New Entries (all their New cards), continuing the step-2 walk past the limit.
- During catch-up, only the extra batches are walked.
- Offered when at least one New Entry is untaken and not answered today, and `new_words_per_day > 0` (`DailyQueue.canLearnMore`).
- Its answers are normal logs and count from then on.

## Review session

### Session list

- Built from the queue when Review opens, in this order: reviews, re-shows, new cards (`DailyQueue.sessionOrder`).
- A **Forgot** answer re-inserts the card **3 cards later**, or at the end if fewer cards remain (`ReviewSession.reshowGap`). This is a session rule, not in the fixtures.

### Which sentence a card shows

UI only, not in the fixtures (`SentenceRotation.pick`):
- Take the Entry's live Contexts that have a sentence, ordered by `(captured_at, id)`. The card shows the one at index `reps mod count`, where `reps` is the card's value before this answer.
- Recognition may use any sentence.
- Recall and cloze rotate over Contexts that have a highlight only.
- The back reuses the front's sentence.
- Recall without a highlighted sentence shows only the translation(s) on the front.
- Cloze without one falls back to the recall front.

### Undo and commit

The last answer is held **in memory, uncommitted** (`ReviewSession.pending`), so ↶ can undo it.

**Committing an answer** is one transaction (`ToriStore.commitAnswer`):
- insert the ReviewLog;
- run the scheduler step;
- clear `needs_check` (rank 0, only if it is 1);
- write the outbox rows.

**It is committed on the first of these:**
1. The next answer.
2. The session ending: ✕, Done, or reaching the summary.
3. **Learn more new words.**
4. Opening another flow that closes Review (a `toriwords://add` link).
5. **The app going to the background:** `scenePhase` becoming `.background` (`AppEnvironment.didEnterBackground` calls `commitPending`). This also covers locking the screen and switching apps. Becoming inactive alone (Control Center, a system alert) does not commit.

**Running the commit:**
- It runs synchronously in `ToriStore.write` on the main actor, so leaving the screen cannot cancel it half-way.
- **A crash or a force-quit while the screen is visible** (no background transition) loses the one uncommitted answer. This is accepted.

**Undo:**
- ↶ undoes only the uncommitted answer and brings its card back.
- ↶ is hidden when there is nothing to undo.
- Committed answers are permanent: logs are never edited or deleted one by one.

### Other session rules

- **Mid-session edits:** an edited card shows the change immediately, with its schedule unchanged. An Entry deleted or excluded mid-session leaves the list.
- **Session summary**, session-local, from this session's committed answers:
  - cards reviewed = distinct cards answered;
  - remembered = distinct cards whose **first** answer in the session was Remembered;
  - new words = Entries introduced in this session.

### Practice

**Opening it:**
- Opened from Progress → Today ("Practice today's words").
- Offered only when `|answeredToday| > 0`.
- Practice never changes the schedule.

**The session:**
- The list is `answeredToday`, computed when practice opens, shuffled with an unseeded `Array.shuffled()`.
- Each card is shown once: Forgot is **not** re-shown (`reshowsForgot: false`), so the session has exactly `|answeredToday|` cards.
- Answers are **never committed**: no log, scheduler step, `needs_check` clear, outbox row, snapshot, widget or reminder refresh.
- ↶ still undoes the last answer in memory.
- None of the commit triggers above apply. Leaving or backgrounding commits nothing.
- End summary: "N cards · M remembered". It has no next-due line, no Learn more and no reminder offer.

**What practice is not used by:** the reminder, the widget and Home's Review button always open normal review (`toriwords://review`).

**Testing:** a `ToriCoreTests` unit test covers the practice set: today's cards of active Entries only. There is no shared fixture for it.

### After every commit

Refresh the queue numbers (the screens observe the store). Write the App Group files (widget snapshot and vocabulary index, debounced 2 s, flushed on entering the background), then reload the widget timelines and refresh the reminders.

## Stats (Progress)

Opened by tapping the Due today block on Home. Everything is computed on the device from live data (`ProgressStats`). Nothing is stored or synced, and deleted Entries and their logs are excluded.

- **Today:**
  - cards reviewed = `|answeredToday|`;
  - still due = the current Due today count;
  - new words introduced = `|introducedToday|`;
  - "Practice today's words" when cards reviewed > 0.
- **Vocabulary:**
  - Entries by Entry stage (new / learning / known well);
  - "already known" (`excluded_reason = known`);
  - paused.
  - Tapping a number opens the filtered Words list.
- **Activity:** rated logs per `review_day` for days `T−29 … T` (a Swift Charts bar chart).
- **Captured:**
  - Entries created per week for the last 8 weeks, as 7-day blocks of review days ending today (`T−55 … T`). The review day of `created_at` uses the 04:00 boundary and the current offset.
  - The top 5 Sources by number of live Entries with a Context from them. Ties are broken by label (UTF-8 byte order), then ID. Kind `suggested` is not counted.
  - A Source's label is its `title`. Without a title, it is the URL host without a leading `www.`.
- Activity and Today count each log on its own `review_day`, so a time-zone change never moves past reviews.

## Widget snapshot

The widget extension never opens the database. It reads `widget-snapshot.json` from the App Group container, written by the app.

```json
{ "format": 1, "generatedAt": 1762790400000, "utcOffsetMin": 180,
  "days": [ { "day": 20402, "dueReviews": 12, "newAvailable": 5 },
            { "day": 20403, "dueReviews": 19, "newAvailable": 10 } ],
  "nextDueDay": 20402, "homeState": "due" }
```

### Contents

`WidgetSnapshot.compute` (`ToriCore/WidgetSnapshot.swift`):

| Field | Meaning |
|---|---|
| `days` | 7 entries: today and the next 6 days. For day `T+k` (k ≥ 1), the queue rules are applied to that day **assuming no further answers**. Today's committed logs count as history. |
| `dueReviews` | Steps 1 + 3. During catch-up this is today's capped share, never the whole backlog. |
| `newAvailable` | Step 2 (0 during catch-up). |
| `nextDueDay` | The smallest day with `dueReviews + newAvailable > 0`, or null if none. |
| `homeState` | Today's Home state (table above). |

### Writes

- **Atomic:** `AtomicFile` writes a temp file in the same directory, then renames it. JSON keys are sorted.
- Written together with `vocab-index.json` by `ToriStore.writeAppGroupFiles`.
- **Debounced 2 s** after any change that can affect counts (`store.vocabularyChanges()` observation, a committed answer, a bulk change such as a restore):
  - a committed answer;
  - a capture, an inbox import or an Add;
  - a sync apply;
  - a settings change;
  - an Entry being excluded, resumed or deleted.
- **Also written:**
  - at launch;
  - on entering the background (flush);
  - in the background app refresh.
- Each write is followed by `WidgetCenter.shared.reloadAllTimelines()`.
- Skipped when the App Group is unavailable (Personal builds).

### What the widget shows

`WidgetDisplay(snapshot:now:utcOffsetMin:)` computes "today" from the device's offset at the render instant:

| Display | Condition (first match wins) |
|---|---|
| "Open ToriWords" | no snapshot; snapshot older than 7 days (`now − generatedAt > 7 × 86 400 000`); `homeState` is `empty` or `noneReviewable`; today is not among the snapshot's days |
| "N to review · M new" | today's `dueReviews + newAvailable > 0` |
| "Next review: tomorrow" / a date | the first later snapshot day with something to review (never a time) |
| "Open ToriWords" | nothing scheduled within the snapshot's days |

Families: `systemSmall`, `systemMedium`, `accessoryCircular`, `accessoryRectangular`; none when the App Group is unavailable. A tap opens `toriwords://review`. Visuals per family: [ui.md](ui.md).

### WidgetKit timeline

`Provider.getTimeline` returns:
- one entry **now**;
- one entry at each of the next **7** 04:00 day boundaries (`WidgetDisplay.dayBoundaries`), computed in the snapshot's `utcOffsetMin` (the current offset when there is no snapshot);
- reload policy **`.atEnd`**.

Each entry carries the same snapshot; the view recomputes "today" at its date, so the count rolls over at 04:00 without the app running. After the last entry, WidgetKit asks for a new timeline. The app also reloads the timelines after every snapshot write.

## 04:00 rollover

### While the app is in the foreground

Screens recompute "today" whenever the store changes and whenever the scene becomes active again (Home restarts its observation on `scenePhase == .active`). **Not yet implemented:** a timer at the next 04:00 boundary, and a recompute on a clock or time-zone change while the app stays in the foreground. A screen left open across 04:00 shows the old day until the next store change or activation.

### For the widget

The WidgetKit timeline above has an entry at every 04:00 boundary, so the widget needs no alarm or app wake-up to roll over.

## Reminders

### The rule

- One optional daily reminder at a user-chosen time.
- Per device (`UserDefaults`: `reminderEnabled`, `reminderHour`, `reminderMinute`), default off, default time 19:00.
- It fires only on a day whose `dueReviews + newAvailable > 0`.
- Its body is "N to review", where N is that sum. It is the same number as Home's Due today and counts **cards**, not words. It has no title; the system shows "ToriWords".
- There is no streak or nagging copy and no push server.

### Permission

- Notification authorization (`.alert`, `.sound`, `.badge`) is requested **only** when the user turns the reminder on (`ReminderScheduler.setEnabled(true)`).
- The app offers reminders once, after the first finished review session with at least one card reviewed (`reminderOfferShown`).
- If notifications are denied, Settings shows "Notifications are off for ToriWords" with **Open iOS Settings**. The app never re-asks by itself.

### Scheduling

`ReminderScheduler.refresh()`:
1. Remove every pending request whose identifier starts with `reminder-`.
2. If the reminder is on and authorization is `authorized` or `provisional`, compute today's snapshot **from the store** (`StoreReader.widgetSnapshot`, not the App Group file, so it works without an App Group).
3. `ReminderPlan.requests` gives **up to 7** requests, one per snapshot day `d ≥ today` with `dueReviews + newAvailable > 0`:
   - identifier `reminder-<review day>`;
   - fire date: the chosen local time on the review day's calendar date. A reminder time between 00:00 and 04:00 belongs to the previous review day, so it fires on the next calendar date;
   - requests whose fire instant is not after `now` are skipped.
4. Each request uses `UNCalendarNotificationTrigger` with year, month, day, hour and minute, **no time zone** and `repeats: false`, sound default, `userInfo["url"] = toriwords://review`.

Because the date components have no time zone, a request fires at the chosen local time in whatever zone the device is in.

**Refreshed:**
- 2 s after any vocabulary change and after every committed answer (with the App Group files);
- when the setting or time changes;
- at launch, on entering the background and in the background app refresh.

### At fire time

The system delivers the scheduled notification. The count in it was computed at scheduling time. There is no code at fire time and no sync in this path.

The notification tap opens Review: `UNUserNotificationCenterDelegate.didReceive` reads `userInfo["url"]` and opens it on the main thread. The delegate is set before launch finishes, so a tap that cold-starts the app is delivered.

### While the app is open

`willPresent` returns no presentation options: a reminder that fires while the app is in the foreground shows no banner. When the user finishes today's queue, the next refresh (2 s after the last commit) drops today's request, because today's sum is now 0.

### Limits

- **Exact:** calendar triggers fire at the chosen time.
- **Precomputed counts:** each day's N is the snapshot's projection for that day at the last refresh. Words added or reviews done later change it only after the app runs again (foreground, background refresh, or a sync followed by a refresh). A day that had nothing scheduled at the last refresh gets no reminder until the app refreshes.
- **Other devices:** reviews done on another device count only after this device syncs and refreshes.
- **7-day horizon:** if the app is not opened and no background refresh runs for 7 days, no requests are left.
- **Comparison:** Android checks the count live at fire time instead.

## Widget hint

How to add the Home Screen widget (`App/Shared/WidgetHint.swift`; behaviour in [product.md](product.md)):
- **On the Add screen after a save**, when no ToriWords widget is placed (`WidgetCenter.shared.currentConfigurations()` is empty) and the hint is not snoozed. **Not now** snoozes it for 24 hours (`@AppStorage("widgetHintSnoozedUntil")`, a per-device value).
- **In Settings → Widget**, always available.
- Text steps only (Edit → Add Widget). iOS has no API that lets an app place a widget.

## Open questions

1. **Monotonic answer time.** Whether `answer_ms` should use a monotonic clock (for example `ContinuousClock`) instead of wall-clock milliseconds.
2. **Foreground rollover.** Whether to add a 04:00 timer and clock or time-zone change handling while the app is in the foreground, as Android does, or rely on the next activation.
3. **libm parity.** Whether to pin `pow`/`exp` to a portable implementation, as Android pins fdlibm, or keep relying on the fixture tolerance.
