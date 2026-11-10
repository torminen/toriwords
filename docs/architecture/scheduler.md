# Scheduler

Status: **Confirmed** (owner, 2026-11-10). Confirmed: FSRS-6 with default parameters, desired retention 0.90 hidden from the user, own implementation per platform, whole-day intervals with a 04:00 rollover, the sibling rule (PD-1) and the daily queue (PD-4). Open: Q-S3 (per-user optimiser, after v1). The default `w` values must still be checked against the pinned reference (§5.6).

The scheduler decides when each Card is next due. Both apps implement it natively ([native apps](memory://7)), so it is specified here precisely enough for two independent implementations to give **bit-for-bit identical due days** for the same review history. Cross-platform fixtures live in [parity-testing.md](parity-testing.md).

Inputs: the Card and ReviewLog concepts in [domain-model.md](../product/domain-model.md). Related: [local-storage.md](local-storage.md), [sync.md](sync.md), analysis §7, A7, A12, I4, I9.

## 1. Choice of algorithm

| Option | For | Against |
|---|---|---|
| **SM-2** (SuperMemo 2 / Anki legacy) | Tiny, well known, trivially portable. | "Ease hell"; punishes missed days with rigid intervals; no recall probability, so no "target retention" and no principled handling of overdue cards (I4); needs Hard/Easy buttons to adapt ease, which conflicts with simple grading (I2). |
| **Leitner boxes** | Simplest to explain. | Coarse; ignores how overdue a card is; no evidence base. |
| **FSRS-6** (Free Spaced Repetition Scheduler, open source, Anki's optional scheduler since 23.10, v6 since 25.07) | Best published recall prediction (beats SM-2 on ~99.6% of ~10K collections in the open benchmark, analysis §7); handles overdue cards using real elapsed time, which helps graceful catch-up after breaks (I4); works with two buttons (Again/Good); target retention is one understandable setting; formulas are public and small; Anki revlogs fit it directly (future import). | More maths than SM-2; per-user parameter optimisation is heavy (not needed in v1, see §6); two implementations must agree on floating-point details (handled in §8). |
| FSRS-5 | Mature libraries. | Superseded; FSRS-6 adds a trainable forgetting-curve shape (w20) and better same-day review handling. |

**Recommendation: FSRS-6** with the default parameters, a desired retention of 0.90, and whole-day intervals (§4).

## 2. Libraries vs own implementation

| Option | For | Against |
|---|---|---|
| (a) Third-party libraries per platform | Less code to write. | As of Nov 2026 the official org's Swift package (`open-spaced-repetition/swift-fsrs`) implements FSRS-5 and was last pushed Dec 2024; the official Android repo (`android-fsrs`) is v4. FSRS-6 ports exist but are unofficial and young (Swift: `bitbemol/swift-fsrs` pre-1.0, `bootuz/SwiftFSRS`; Kotlin: `FsrsKt` on Maven Central; awesome-fsrs also lists an `FSRS-Kotlin` v6 entry, not verified). Two independent libraries will differ in fuzz, learning steps, rounding and day handling, which breaks parity. Maintenance risk. |
| (b) **Own implementation of this spec on each platform** | ~200–300 lines per platform. We control every rounding and day rule. Parity is checked against the shared fixtures. | We own correctness, so the fixtures must be generated from a reference implementation. |

**Recommendation: (b).** The reference for generating fixtures is the official **py-fsrs** (or `fsrs-rs`) at a pinned FSRS-6 release, wrapped by a fixture-generator script that applies the Toriwords-specific rules in §4–§7 (no minute steps, deterministic fuzz). The generator is specified in [parity-testing.md](parity-testing.md); it is a dev tool, not app code. MIT-licensed references, so no licence issue ([open source](memory://12)).

## 3. Grading → FSRS rating

FSRS ratings: `Again = 1`, `Hard = 2`, `Good = 3`, `Easy = 4`. The product grading scheme is two buttons (PD-2, confirmed). Mapping, including the alternatives kept for reference and import:

| Product scheme | Mapping |
|---|---|
| **Two buttons (v1, PD-2):** "Forgot" / "Remembered" | Again / Good. Hard and Easy are never produced; FSRS-6 works without them. |
| Four buttons (Anki-style) | One to one. |
| Inferred from a typed answer (if a typing exercise is adopted) | Exact match → Good; accepted with a typo tolerance or after a hint → Hard; wrong or "show answer" → Again. The typo rule must itself be in the fixtures. |

Rules:
- The stored ReviewLog `rating` is always the **FSRS rating (1–4)**, whatever UI produced it. The UI scheme can then change later without migrating history.
- An imported Anki answer stores Anki's button 1–4 as its FSRS `rating` **one to one**, also under a two-button UI. Anki's buttons are the FSRS buttons, and collapsing Hard/Easy into Good would throw away scheduling information. `original rating` keeps the same value for display.
- `rating` is **nullable only for imported rows that are not answers** (§7.1). Logs written by Toriwords always have a rating.

## 4. Time model: days, not minutes

- **Intervals are whole days.** There are no minute-level learning steps. A failed or new card that should be seen again "soon" is re-shown **later in the same session** by the review queue (product behaviour), and each re-show is a normal ReviewLog on the same day.
  - Why: Anki-style 1m/10m steps add a second, minute-based scheduler, more states and more parity surface, for little benefit to a vocabulary learner. FSRS-6 models same-day reviews explicitly (§5.4), so they still count.
- **Day boundary: 04:00 local time.** A "day" runs from 04:00 to 04:00 the next morning in the device's time zone. Reviews done at 01:30 count for the previous day, like Anki. The 04:00 value is a constant in v1, not a setting.
- **Day number.** For an instant `t` (UTC) and a UTC offset `o` (minutes):

  ```
  dayNumber(t, o) = floor( (t_epoch_seconds + o*60 − 4*3600) / 86400 )
  ```

  Integer arithmetic with a mathematical floor (rounds toward −∞).
- **Review day of a ReviewLog** = `dayNumber(reviewedAt, offsetAtReview)`. The domain model already stores the UTC offset with `reviewed at`. The review day is therefore fixed forever at write time and **replay never depends on the current time zone**.
- **Today** = `dayNumber(now, current device offset)`.
- **Time-zone change.** Nothing stored is rewritten. "Today" is computed with the new offset, so after flying east a card may become due a few hours earlier, and after flying west a little later. A day can look 20 or 28 hours long. The scheduler tolerates this: `elapsedDays` is computed from review days, never negative (clamped to ≥ 0).
- **Wrong device clock.** `reviewedAt` comes from the device clock and is stored as given; nothing corrects it. Because elapsed days are clamped at 0 and replay sorts by `(reviewedAt, id)`, a clock set to the future only makes that one review count on a later day. A clock set to the past makes it sort earlier. Both outcomes are deterministic on every device after sync. The app may warn when the clock differs from the server time by more than a day at sync time ([sync.md](sync.md)), but the scheduler never depends on that.
- **Due** is stored as a day number (`dueDay`). A Card is **due** when `dueDay ≤ today`. That definition is used everywhere: review queue, due count, widget, reminders ([capture-and-extensions.md](capture-and-extensions.md)).

## 5. FSRS-6 formulas

Notation: `w[0..20]` parameters, `G` rating 1–4, `S` stability (days), `D` difficulty in [1, 10], `R` retrievability, `t` elapsed days (integer, ≥ 0). All arithmetic in IEEE-754 binary64 (`Double`).

### 5.1 Forgetting curve
```
decay  = −w[20]
factor = 0.9^(1/decay) − 1
R(t, S) = (1 + factor · t / S)^decay
```

### 5.2 Interval for desired retention r
```
I(r, S) = S / factor · (r^(1/decay) − 1)
interval = clamp( roundHalfUp(I), 1, maximumInterval )
```
`roundHalfUp(x) = floor(x + 0.5)`. `maximumInterval = 36500` days.

### 5.3 First review of a new Card
```
S0(G) = w[G−1]
D0(G) = w[4] − e^(w[5]·(G−1)) + 1          (clamped to [1, 10] when stored)
```

### 5.4 Next state for a Card that has a state (S, D), last review day L, reviewed on day T with rating G
`t = max(0, T − L)`.

**Difficulty** (all ratings):
```
ΔD   = −w[6] · (G − 3)
D'   = D + ΔD · (10 − D) / 9
D''  = w[7] · D0(4) + (1 − w[7]) · D'       (D0(4) unclamped)
Dnew = clamp(D'', 1, 10)
```

**Stability:**
- **Same-day review** (`t = 0`):
  ```
  SInc = e^(w[17] · (G − 3 + w[18])) · S^(−w[19])
  if G ≥ 3: SInc = max(SInc, 1)
  Snew = S · SInc
  ```
- **Successful review** (`t ≥ 1`, `G ≥ 2`), with `R = R(t, S)`:
  ```
  hardPenalty = (G == 2) ? w[15] : 1
  easyBonus   = (G == 4) ? w[16] : 1
  Snew = S · ( e^w[8] · (11 − D) · S^(−w[9]) · (e^(w[10]·(1 − R)) − 1) · hardPenalty · easyBonus + 1 )
  ```
- **Lapse** (`t ≥ 1`, `G = 1`), with `R = R(t, S)`:
  ```
  Sf   = w[11] · D^(−w[12]) · ((S + 1)^w[13] − 1) · e^(w[14] · (1 − R))
  Snew = min(Sf, S / e^(w[17] · w[18]))
  ```
- `Snew` is clamped to `[0.001, 36500]`.
- `D` in the stability formulas is the difficulty **before** this review's update.

### 5.5 Due day after a review on day T
| Case | dueDay |
|---|---|
| `G = 1` (any card) | `T` (shown again later in today's session; still due today if the session ends) |
| New card (first review) with `G = 2` | `T` (re-shown the same day once more) |
| Otherwise | `T + fuzz(interval(r, Snew))` |

### 5.6 Default parameters (FSRS-6)
```
w = [0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722,
     0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425,
     0.0912, 0.0658, 0.1542]
desiredRetention = 0.90
```
These values are recalled from the py-fsrs FSRS-6 defaults. **They must be checked against the pinned reference release before the fixtures are generated** (the fixtures, not this table, are the final authority).

## 6. Parameters per user

- v1 ships the default `w` and `desiredRetention = 0.90`. No optimiser in the apps.
  - Options for later: (a) on-device optimiser (heavy, two implementations of gradient descent = parity nightmare); (b) **backend job** using `fsrs-rs` over the user's synced logs, returning a new `w` (one implementation, only for signed-in users); (c) never. Recommendation for after v1: (b).
- A parameter set is versioned data: `{ paramsId, w[21], desiredRetention }`, synced as a user setting. Changing it does **not** rewrite history; the Card state is recomputed by replay (§7).
- Whether desired retention is user-visible is a product question (analysis X6 warns against settings overload). Recommendation: hidden in v1.

## 7. Card state is derived from the log

**Rule: a Card's scheduling state is a pure function of (its ReviewLogs, the parameter set).** The stored state on the Card is a cache.

Cached fields: `stability`, `difficulty`, `lastReviewDay`, `dueDay`, `reps`, `lapses`, `stage`.

**Replay:**
1. Take the ReviewLogs of the **canonical** Card. These are the logs of the Card itself plus those of every Card that merged into it ([sync.md](sync.md) §7.3). Sort them by `(reviewedAt, id)` ascending (id = UUIDv7 bytes, unsigned lexicographic, as a tie-breaker).
2. **Skip logs with no `rating`** (§7.1).
3. Fold §5 over the remaining logs, starting from "new". Imported answers are replayed like native ones; review type and elapsed days are derived here, never read from storage.
4. The result replaces the cache. The fuzz seed (§9) uses the canonical Card id and the 1-based ordinal of the log among the non-skipped logs.

### 7.1 Imported rows that are not answers

Anki's revlog contains rows that record an action rather than an answer: **manual** rows (set due date, Forget/reset) and **rescheduled** rows. Anki stores them with button `0`.

**Rule: they are imported for history with `rating = NULL` and the scheduler ignores them.** Their kind, interval and other details stay in the `original *` fields, which the scheduler never reads.

| Option | For | Against |
|---|---|---|
| **(a) Ignore (recommended)** | One simple rule ("no rating → not an answer"); the scheduler stays independent of Anki's vocabulary; FSRS rebuilds the state from the real answers, which is how Anki's own FSRS treats these rows. | A user's manual "Forget" in Anki does not reset the Toriwords state. FSRS still sees the full answer history, which is arguably more accurate. |
| (b) Treat a reset row as "start from new" | Mirrors the Anki state exactly. | The scheduler must read `original kind`, which ties it to Anki semantics; reset detection in Anki revlogs is heuristic. |

Filtered-deck (cram) rows that have a button 1–4 **are** answers and are replayed.

**When to replay:**
- After a local review: apply one step incrementally (identical result to full replay, by construction).
- After sync brings in ReviewLogs for a Card from another device that are **older** than the Card's newest local log: full replay of that Card. Concurrent offline reviews on two devices thus merge into one deterministic state ([sync.md](sync.md)).
- After a parameter change, an Anki import, or an Entry merge that changes a Card's canonical Card: full replay of the affected Cards.
- Cost: replay is O(logs per card); even 100 logs × 20 000 cards is well under a second in native code.

**Excluded Entries** keep their Cards and logs; the cache stays as is, and the Card simply isn't queued. On resume, the Card is due by its existing `dueDay` (probably overdue, which FSRS handles with the real elapsed time).

**Imported history (after v1):** imported Anki revlogs become ReviewLogs (review type `imported`, rating = Anki button); replay produces the FSRS state. Anki's sub-day learning steps collapse into same-day reviews (§5.4), which is what FSRS-6 was trained on.

## 8. Determinism rules

1. Binary64 everywhere; no `Float`. Use the platform `pow`/`exp` (Swift `Foundation.pow/exp`, Kotlin `kotlin.math.pow/exp`). They may differ in the last ulp; this cannot change a stored day except at an exact `.5` rounding edge, which the fixtures test and tolerate in S/D (`1e-9` relative) but **not** in `dueDay` (must be exact).
2. No randomness except §9 fuzz, which is seeded deterministically.
3. No wall-clock reads inside the scheduler: `today`, review days and parameters are passed in.
4. All day maths in 64-bit integers.

## 9. Interval fuzz (deterministic)

Fuzz spreads cards added together so they don't all fall due on the same day. It is applied only when `interval ≥ 3` (after rounding).

```
ranges = [(2.5, 7.0, 0.15), (7.0, 20.0, 0.10), (20.0, ∞, 0.05)]
delta  = 1.0 + Σ over ranges of factor · max(0, min(interval, end) − start)
lo     = max(2, roundHalfUp(interval − delta))
hi     = min(roundHalfUp(interval + delta), maximumInterval)
u      = seed(cardId, reps) ∈ [0, 1)
fuzzed = lo + floor(u · (hi − lo + 1))
```

`seed(cardId, reps)`: SHA-256 of the 16 raw bytes of the Card's UUID followed by `reps` (the 1-based number of this review) as a 4-byte big-endian unsigned integer. Take the first 8 bytes of the digest as an unsigned big-endian integer, shift right by 11, and divide by 2^53. Same history → same fuzz on both platforms and on every replay.

## 10. Card stage (shown to the user)

The domain model's `learning stage`:

| Stage | Rule |
|---|---|
| `new` | No ReviewLogs. |
| `learning` | Has ReviewLogs, and (`stability < 21` days or the last rating was Again). |
| `known well` | `stability ≥ 21` days and the last rating was not Again. |

The 21-day threshold mirrors Anki's "mature" cut-off. It is a product-tunable constant, fixed in the fixtures.

## 11. Daily queue and catch-up (PD-4)

PD-4 and [review](../product/features/review.md) set the product intent:
- after a break, the backlog is spread over about a week;
- new words pause while catching up;
- "Review all now" is available.

**This section is the single source of truth for the exact numbers.** It makes them exact, so that the home screen, widget and reminder show the **same numbers on every device with the same synced data**. Everything is computed from synced data (ReviewLogs, Cards, Entries, synced settings) plus `today`, and nothing about the queue is stored.

**Sets**, for today `T`, over canonical Cards of `active`, reviewable Entries:
- **Started** Card: has at least one rated log before day `T`. **New** Card: no rated log before day `T`.
- `reviewedToday` = Started Cards with at least one rated log on day `T`.
- `waiting` = Started Cards with `dueDay ≤ T` and no rated log on day `T`.
- `introducedToday` = Cards whose first rated log is on day `T`.

**Normal load:**
```
activeDays = the last 14 distinct review days before T that have ≥ 1 rated log
reviewsInActiveDays = number of (Card, day) pairs on those days where the Card was Started before that day
normalLoad = activeDays empty ? 50 : max(50, ceil(reviewsInActiveDays / |activeDays|))
```

**Catch-up mode:**
```
load    = |waiting| + |reviewedToday|
catchUp = load > 2 · normalLoad
quota   = catchUp ? normalLoad + ceil((load − normalLoad) / 3) : ∞
```
- `normalLoad` depends only on days before `T`, and reviewing moves a Card from `waiting` to `reviewedToday`, so `load`, `catchUp` and `quota` stay constant while the user reviews. They change within a day only when sync brings in another device's logs, or when the user excludes or resumes Entries.
- The floor of 50 (the product's minimum normal day) keeps catch-up from triggering for new users with little history. With an inflow of about `normalLoad` per day, the excess above `normalLoad` shrinks by about a third per day. Catch-up ends when `load ≤ 2 · normalLoad`. That takes about 6 days for a backlog of 13 normal days, and longer for larger backlogs. This is how "about a week" is implemented.
- **Rejected alternative:** `quota = max(normalLoad, ceil(load / 7))`, recomputed daily. With a daily inflow near `normalLoad`, the backlog settles at about 7 × inflow and catch-up never ends. A fixed seven-day plan would need the backlog size stored at the start of catch-up as synced state, which this stateless formula avoids.
- "Most at-risk first" means the order below.

**Today's queue:**
1. **Reviews:** `waiting` Cards in order: retrievability `R(T − lastReviewDay, S)` ascending, then `dueDay` ascending, then Card id. Take the first `max(0, quota − |reviewedToday|)` of them.
2. **New Cards:** `0` in catch-up mode. Otherwise `max(0, newLimit − |introducedToday|)` New Cards, ordered by Entry creation time, then direction (`recognition` before `recall` before `cloze`), then Card id.
3. **Siblings** ([PD-1](../product/proposed-decisions.md#pd-1-card-directions-and-exercise-types), confirmed): walking the combined list (reviews first, then new), skip a Card if another Card of the same Entry has a rated log on day `T` or was already taken earlier in the walk. Skipped Cards stay due and come first by order on a later day.
4. **Same-day re-shows:** Cards answered Forgot today have `dueDay = T` and are re-shown within the session (§5.5). They are in `reviewedToday` and are not limited by the quota.

**Numbers shown:**
- **"Due today"** (home, widget, reminder) = reviews taken in step 1 after the sibling rule + new Cards taken in step 2 after the sibling rule.
- In catch-up, the home screen also shows `|waiting|` as "N waiting".
- **"Next due"**, when nothing is due today, is a **day**, not a time: the smallest `dueDay > T` ("tomorrow", or a date). Scheduling is day-based, so there is no exact time.
- **"Review all now"** and **"Learn more new words"** are **device-local, session-only overrides**: they extend the current session's list on this device only and store nothing; nothing about them is synced, and the other devices' numbers are unaffected until the resulting ReviewLogs sync. Answers made through them are ordinary ReviewLogs, and they count in `reviewedToday` and `introducedToday` from then on.

All of the above goes into the queue fixtures ([parity-testing.md](parity-testing.md)).

## 12. Open questions

- **Q-S1: closed.** Two-button grading (PD-2, confirmed). Four buttons would need no change here.
- **Q-S2: closed.** Desired retention 0.90 is hidden in v1. It is still a synced setting (PD-16), so a later UI can expose it.
- **Q-S3 (owner): open, after v1.** Should a signed-in user get per-user parameters from a backend optimiser (§6 option b)?
- **Q-S4: closed.** The review-day start is a constant 04:00 and not a setting (PD-16, confirmed).
