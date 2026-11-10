# Scheduler

Status: **Proposed**. Pending owner confirmation in step 5. Nothing here is a `decision` yet.

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

FSRS ratings: `Again = 1`, `Hard = 2`, `Good = 3`, `Easy = 4`. The product grading scheme is pending (PD-2). Mapping per candidate:

| Product scheme | Mapping |
|---|---|
| Two buttons (recommended by the analysis, I2): "Don't know" / "Know" | Again / Good. Hard and Easy are never produced; FSRS-6 works without them. |
| Four buttons (Anki-style) | One to one. |
| Inferred from a typed answer (if a typing exercise is adopted) | Exact match → Good; accepted with a typo tolerance or after a hint → Hard; wrong or "show answer" → Again. The typo rule must itself be in the fixtures. |

Rules:
- The stored ReviewLog `rating` is always the **FSRS rating (1–4)**, whatever UI produced it. The UI scheme can then change later without migrating history.
- An imported Anki log stores Anki's 1–4 as `original rating`; its FSRS rating is the same value (Anki's buttons are the FSRS buttons).

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
1. Take the Card's ReviewLogs, sorted by `(reviewedAt, id)` ascending (id = UUIDv7 bytes, unsigned lexicographic, as a tie-breaker).
2. Fold §5 over them, starting from "new". A log of review type `imported` is replayed like any other.
3. The result replaces the cache.

**When to replay:**
- After a local review: apply one step incrementally (identical result to full replay, by construction).
- After sync brings in ReviewLogs for a Card from another device that are **older** than the Card's newest local log: full replay of that Card. Concurrent offline reviews on two devices thus merge into one deterministic state ([sync.md](sync.md)).
- After a parameter change, an Anki import, or an Entry merge that moves logs: full replay of affected Cards.
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

## 11. Daily load (inputs for product, I4)

The scheduler only answers "which Cards are due". The queue rules are a product decision, but they must be deterministic for counts to match across devices:

- **New Cards per day:** a limit (product default, e.g. 10). The count of new Cards introduced today = Cards whose first ReviewLog has review day = today, **across all synced devices**.
- **Review order:** due Cards sorted by `dueDay` ascending, then by retrievability ascending (most forgotten first), then by Card id. After a long break, FSRS needs no special "catch-up mode": overdue Cards keep their real elapsed time, and a product-level daily review cap (if any) only limits how many are shown today.
- **Siblings:** if an Entry has several Cards (PD-1), the queue shows at most one of them per day unless the others are already overdue by more than their interval. (Proposed; product to confirm.)

## 12. Open questions

- **Q-S1 (product, PD-2):** two-button grading assumed as the default mapping. Four buttons are also supported without changes here.
- **Q-S2 (product):** is desired retention user-visible? Recommendation: no.
- **Q-S3 (owner):** after v1, should a signed-in user get per-user parameters from a backend optimiser (§6 option b)?
