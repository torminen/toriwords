# Scheduler, daily queue, review sessions, widget and reminders

How ToriWords decides what to review and when, on Android. The rules are shared with the iOS app and must give **bit-identical due days** for the same history.

**Fixtures win.** The JSON cases in `spec/fixtures/scheduler/` are normative:
- `fsrs-step.json`
- `fsrs-replay.json`
- `day-boundary.json`
- the `queue-*.json` files
- `snapshot.json`

Their case format and tolerances are in `spec/fixtures/README.md`. If this file and a fixture disagree, the fixture is right and this file gets fixed. How the Android suites run them: [testing.md](testing.md).

Related files:
- [data-model.md](data-model.md): `card` and `review_log` columns, settings.
- [sync.md](sync.md): how logs from other devices arrive.
- [architecture.md](architecture.md): modules, WorkManager and alarms in general.

All logic in this file lives in the pure-Kotlin `core` module. Time is always passed in through a `Clock` interface, and `core` never reads the system clock or time zone itself.

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

- Use `Long` and `Math.floorDiv` at both steps (floor toward −∞, also for instants before 1970).
- The **review day** of a log is `dayNumber(reviewed_at, utc_offset_min)`. It is fixed when the log is written, so replay never depends on the current time zone.
- **Today** is `dayNumber(now, currentOffsetMin)`.
- A card is **due** when `due_day ≤ today`. This one rule is used everywhere: queue, Home, widget, reminders and stats.

### Android time sources

| Value | Source |
|---|---|
| `now` | `System.currentTimeMillis()`, behind the `Clock` interface (tests inject fixed instants). Every stored instant comes from it: `reviewed_at`, `created_at`, `captured_at`. |
| Current offset | `ZoneId.systemDefault().rules.getOffset(Instant.ofEpochMilli(now)).totalSeconds / 60`. Read at the moment of use and never cached across a time-zone change. A log's `utc_offset_min` is the offset at answer time. |
| `answer_ms` | Time from the card being shown to the answer, measured with `SystemClock.elapsedRealtime()` (monotonic, unaffected by clock changes). Capped at 600 000 ms. |

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

- `w` and the retention are identical to py-fsrs 6.3.3.
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

`seed(cardId, reps)`, in Kotlin:
1. Take `MessageDigest.getInstance("SHA-256")` over the 16 raw bytes of the **canonical** card ID, followed by `reps` as a 4-byte big-endian unsigned integer.
2. Read the first 8 digest bytes as a big-endian `Long` `x`.
3. Compute `u = (x ushr 11).toDouble() / 9007199254740992.0` (2^53).

### Numerics (Android)

- Use `Double` (binary64) only, never `Float`.
- Use **`StrictMath.pow` and `StrictMath.exp`** (fdlibm), not `kotlin.math` or `Math`. The host JVM (where the fixture suite runs on every CI build) and every ART device then produce the same bits.
- `roundHalfUp(x) = floor(x + 0.5)` with `kotlin.math.floor`. Day arithmetic is in `Long`.
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
5. Fold the FSRS steps from "new".
6. Write the cache.

Review type and elapsed days are derived during the fold, never read from storage. `review_log.review_type` is never filled.

### Stage

| Stage | Condition |
|---|---|
| `new` | No rated logs. |
| `known_well` | `stability ≥ 21` and the last rating ≠ 1. |
| `learning` | Everything else. |

**Entry-level stage** (Words list, Progress). It applies to active Entries that have a translation. The full marker order (Needs translation → Known → Paused → stage) is in [domain.md](domain.md#entry).

| Entry stage | Condition |
|---|---|
| **New** | None of its live cards has a rated log, or it has no cards. |
| **Known well** | Every live card is `known_well`. |
| **Learning** | Everything else. |

### When replay runs

| Event | Replay |
|---|---|
| Committed local answer | One incremental step (equal to a full replay by construction). |
| A pull brings logs for a card | Full replay of that card. |
| A duplicate merge changes a card's canonical card, a restore | Full replay of the affected cards. |
| Change of `fsrs_w`, `desired_retention` or `scheduler_version` (local or pulled) | Full rebuild of every card. It runs in the application scope on `Dispatchers.Default` and the UI stays usable. Its time target is owned by [architecture.md](architecture.md#14-performance-targets). |

- Resuming an excluded Entry triggers **no** replay. Excluded Entries keep their cache and are simply not queued, so on resume their existing `due_day` applies.

### Which cards exist

Cards exist only for canonical, live, `active` Entries that have a live Sense with a non-empty translation. Entries without a translation never appear in Review, the widget or Home counts.

## Daily queue

The queue is computed from synced data plus today (`T`) only. Nothing about it is stored. It runs over the canonical cards of live, `active`, reviewable Entries.

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

Catch-up spreads a backlog over several days. There is **no "Review all now" control** on Android: the quota cannot be lifted.

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
- **Next due**, when nothing is due: the smallest `due_day > T`, shown as a day ("tomorrow" or a date), never a time.

**Home "Due today" states**, also written to the widget snapshot:

| State | Condition (first match wins) |
|---|---|
| `empty` | No live Entries. |
| `due` | The queue is non-empty. |
| `allDone` | The queue is empty and at least one rated log exists on `T`. |
| `noneReviewable` | Live Entries exist, none has a live card, **and** at least one live Entry needs a translation (no Sense with a translation, see [domain.md](domain.md#entry)). |
| `nothingDue` | Everything else: "Nothing to review today", or the "Next review…" line when a card is scheduled. |

- Example: every Entry has a translation but all are Known or Paused, so no live card exists. That is `nothingDue`, not `noneReviewable`.
- This differs from iOS on purpose. iOS shows `noneReviewable` whenever no live card exists, even when 0 words need a translation.

### Learn more new words

- A device-local, session-only extension of the current session. Nothing about it is stored or synced.
- Each tap appends one more batch of `new_words_per_day` New Entries (all their New cards), continuing the step-2 walk past the limit.
- During catch-up, only the extra batches are walked.
- Offered when at least one New Entry is untaken and not answered today, and `new_words_per_day > 0`.
- Its answers are normal logs and count from then on.

## Review session

### Session list

- Built from the queue when Review opens, in this order: reviews, re-shows, new cards.
- A **Forgot** answer re-inserts the card **3 cards later**, or at the end if fewer cards remain. This is a session rule, not in the fixtures.

### Which sentence a card shows

UI only, not in the fixtures:
- Take the Entry's live Contexts that have a sentence, ordered by `(captured_at, id)`. The card shows the one at index `reps mod count`, where `reps` is the card's value before this answer.
- Recognition may use any sentence.
- Recall and cloze rotate over Contexts that have a highlight only.
- The back reuses the front's sentence.
- Recall without a highlighted sentence shows only the translation(s) on the front.
- Cloze without one falls back to the recall front.

### Undo and commit

The last answer is held **in memory, uncommitted**, so ↶ can undo it.

**Committing an answer** is one transaction:
- insert the ReviewLog;
- run the scheduler step;
- clear `needs_check` (rank 0, only if it is 1);
- write the outbox rows.

**It is committed on the first of these:**
1. The next answer.
2. The session ending: ✕, Done, system Back or predictive Back (Back acts as ✕ in Review), or reaching the summary.
3. **Learn more new words.**
4. Opening another flow that closes Review.
5. **The app going to the background:** the Review host activity's `onStop` **when `isChangingConfigurations` is false**. Rotation, resizing and theme changes do not commit. This also covers the screen turning off and switching apps.

**Running the commit:**
- It runs in the application `CoroutineScope` under `NonCancellable`, so leaving the screen cannot cancel it half-way.
- **A crash or a force-stop while the screen is visible** (no `onStop`) loses the one uncommitted answer. This is accepted.

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
- The list is `answeredToday`, computed when practice opens, shuffled with an unseeded `kotlin.random.Random`.
- Each card is shown once: Forgot is **not** re-shown, so the session has exactly `|answeredToday|` cards.
- Answers are **never committed**: no log, scheduler step, `needs_check` clear, outbox row, snapshot, widget or reminder refresh.
- ↶ still undoes the last answer in memory.
- None of the commit triggers above apply. Leaving or backgrounding commits nothing.
- End summary: "N cards · M remembered". It has no next-due line, no Learn more and no reminder offer.

**What practice is not used by:** the reminder, the widget and Home's Review button always open normal review.

**Testing:** a JVM unit test in `core` covers the practice set: today's cards of active Entries only. There is no shared fixture for it.

### After every commit

Refresh the queue numbers. Write the snapshot (debounced 2 s, flushed on the app's `ON_STOP`), then update the widget and re-arm the reminder.

## Stats (Progress)

Opened by tapping the Due today block on Home. Everything is computed on the device from live data. Nothing is stored or synced, and deleted Entries and their logs are excluded.

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
- **Activity:** rated logs per `review_day` for days `T−29 … T`.
- **Captured:**
  - Entries created per week for the last 8 weeks, as 7-day blocks of review days ending today (`T−55 … T`). The review day of `created_at` uses the 04:00 boundary and the current offset.
  - The top 5 Sources by number of live Entries with a Context from them. Ties are broken by label, then ID. Kind `suggested` is not counted.
  - A Source's label is its `title`. Without a title, it is the URL host without a leading `www.`.
- Activity and Today count each log on its own `review_day`, so a time-zone change never moves past reviews.

## Widget snapshot

The widget never opens the database. It reads `noBackupFilesDir/widget-snapshot.json`, written by the app (same process).

```json
{ "format": 1, "generatedAt": 1762790400000, "utcOffsetMin": 180,
  "days": [ { "day": 20402, "dueReviews": 12, "newAvailable": 5 },
            { "day": 20403, "dueReviews": 19, "newAvailable": 10 } ],
  "nextDueDay": 20402, "homeState": "due" }
```

### Contents

| Field | Meaning |
|---|---|
| `days` | 7 entries: today and the next 6 days. For day `T+k` (k ≥ 1), the queue rules are applied to that day **assuming no further answers**. Today's committed logs count as history. |
| `dueReviews` | Steps 1 + 3. During catch-up this is today's capped share, never the whole backlog. |
| `newAvailable` | Step 2 (0 during catch-up). |
| `nextDueDay` | The smallest day with `dueReviews + newAvailable > 0`, or null if none. |
| `homeState` | Today's Home state (table above). |

### Writes

- **Atomic:** a temp file, then rename.
- **Debounced 2 s** after any change that can affect counts:
  - a committed answer;
  - a capture or an Add;
  - a sync apply;
  - a settings change;
  - an Entry being excluded, resumed or deleted.
- **Also written:**
  - on the app's `ON_STOP` (flush);
  - on the day-rollover alarm;
  - after time or time-zone changes;
  - on boot.
- Each write is followed by `TodayWidget().updateAll(context)`.

The widget computes "today" from the current offset when it renders. What it shows for each state: [ui.md](ui.md).

## 04:00 rollover

### While the app is in the foreground

A coroutine waits until the next 04:00 boundary instant, then recomputes the queue, Home and the snapshot. It re-arms after `ACTION_TIME_CHANGED` and `ACTION_TIMEZONE_CHANGED`.

### For the widget

Use one **inexact, non-wakeup** alarm: `AlarmManager.set(RTC, nextBoundaryMs, pendingIntent)` at the next 04:00 local boundary.
- It needs no exact-alarm permission.
- A non-wakeup alarm is delivered when the device is next awake, which is when a widget can be seen.

The receiver (`goAsync()`, or an expedited worker if the work takes more than a few seconds):
1. waits for app start-up to finish;
2. rewrites the snapshot;
3. updates the widget;
4. arms the next boundary.

**Re-arming:**
- The alarm is re-armed on every app start-up, on boot, on time and time-zone changes, and after an app update.
- `PendingIntent`s use `FLAG_IMMUTABLE | FLAG_UPDATE_CURRENT` with fixed request codes, so re-arming is idempotent.

The accepted lag is up to about an hour; typically it is minutes.

## Reminders

### The rule

- One optional daily reminder at a user-chosen time.
- Per device, default off, default time 19:00.
- It fires only when today's `dueReviews + newAvailable > 0`.
- Its body is "N to review", where N is that sum. It is the same number as Home's Due today and counts **cards**, not words.
- There is no streak or nagging copy and no push server.

### Permission

- `POST_NOTIFICATIONS` is requested (Android 13+) only when the user turns the reminder on.
- The app offers reminders once, after the first finished review session.
- On Android 12 there is no runtime prompt. The app checks `NotificationManagerCompat.areNotificationsEnabled()` and the channel's importance.
- If notifications are blocked, Settings shows that notifications are off, with a link to `Settings.ACTION_APP_NOTIFICATION_SETTINGS`. The app never re-asks by itself.

### Channel

`reminders` ("Daily reminder"), importance default, created at first use.

### Scheduling

Use one inexact **allow-while-idle** alarm: `AlarmManager.setAndAllowWhileIdle(RTC_WAKEUP, fireAt, pi)`. It needs no special permission.
- `fireAt` is the next occurrence of the reminder time in the current zone.
- A reminder time between 00:00 and 04:00 belongs to the previous review day: the fire instant's day is `dayNumber(fireAt, offset)`.

**Re-armed:**
- after each fire;
- when the setting changes;
- on every app start-up;
- on boot, time and time-zone changes;
- after an app update.

After a time-zone change it fires at the chosen local time in the new zone.

### At fire time

The alarm receiver enqueues an expedited `ReminderWorker`. The count is checked live, not precomputed. The worker:
1. waits for app start-up to finish;
2. rewrites the snapshot from the database;
3. reads today's `dueReviews + newAvailable`;
4. if the sum is > 0, posts the notification (fixed ID, `autoCancel`);
5. arms the next day.

The notification tap is a `PendingIntent.getActivity` straight to `MainActivity` with the Review destination. Android 12 blocks notification trampolines through receivers or services. There is no sync in this path: it would delay the reminder.

### While the app is open

When the user finishes today's queue (Home state `allDone`), a posted reminder notification is cancelled.

### Limits

- **Inexact:** usually within minutes of the chosen time, but under deep Doze it can be later. The product copy says "around" the chosen time.
- **Other devices:** reviews done on another device count only after this device syncs.
- **Force-stop:** a force-stop cancels alarms until the app is opened again (an Android rule).
- **Comparison:** iOS schedules up to 7 calendar notifications in advance from the snapshot. Android checks live at fire time instead. The visible behaviour is the same.
