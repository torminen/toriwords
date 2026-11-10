# Review

- **Priority:** P0.
- **Status:** card types pending [PD-1](../proposed-decisions.md#pd-1-card-directions-and-exercise-types), grading pending [PD-2](../proposed-decisions.md#pd-2-grading), daily load pending [PD-4](../proposed-decisions.md#pd-4-daily-load-and-catch-up). The behaviour below follows the recommendations.
- **Analysis:** A2, A7, I2, I4, I9, §6.4, §7, §11 Q6–Q7.
- **Domain:** [Card, ReviewLog](../domain-model.md#card). Scheduling: [scheduler.md](../../architecture/scheduler.md).

## Behaviour

**Starting**
- The home screen shows how many cards are due today and a **Review** button. When nothing is due it shows when the next card is due.
- One queue contains everything due. Tags or sources do not split it (PD-3).

**A card** (recommendation PD-1)
- **Recognition (EN → RU):** the front shows the English word or phrase and its sentence with the word highlighted. Tapping the card flips it.
- **Recall (RU → EN):** the front shows the Russian translation(s) and the sentence with the word blanked.
- The back shows the word, all its meanings (translation, definition, part of speech), IPA, the sentence with source, and a speaker button ([pronunciation](pronunciation.md)).
- If the entry has several sentences, a different one is shown each time.
- Without a sentence, the card shows only the word or translation.

**Grading** (recommendation PD-2)
- After the flip: **Forgot** and **Remembered**. Swiping left or right does the same.
- The next card appears immediately. The scheduler decides when the card is due again; the user never sees intervals or settings unless they open the entry.

**Actions on a card** (from a menu on the back): **Edit** the entry (opens the editor, returns to the same card), **I already know this** (excludes the entry, see [vocabulary management](vocabulary-management.md)), **Pause**, **Delete**.

**Session**
- New cards are mixed in among due reviews, up to the daily new-word limit (default 10).
- At most one card of an entry is shown per day; the other waits until the next day, unless it is already overdue by more than its interval ([scheduler.md](../../architecture/scheduler.md) §11).
- A **Forgot** card comes back later in the same session until it is remembered once.
- Leaving the review at any point keeps every answer already given. There is no "session" to lose.
- When the queue is empty: a short summary (cards reviewed, words remembered, new words introduced). If more new words are waiting, **Learn more new words** introduces another batch of the daily limit.

**Daily load and catch-up** (recommendation PD-4)
- A review day starts at 04:00 local time.
- After a break, when today's due reviews are more than twice the normal load (average reviews per day over the previous 14 days, at least 50): the home screen says "Welcome back — you have N cards waiting. We'll spread them over the next few days." New words pause. Today's queue is capped at the larger of the normal load and a seventh of the backlog, most at-risk cards first. **Review all now** lifts the cap for today on this device. Exact rule: PD-4.
- No guilt messages, no lost streaks.

## Edge cases

- **Entry edited mid-review:** the card shows the edited content right away; the schedule is unchanged.
- **Entry deleted or excluded mid-review:** its cards leave the queue.
- **Same card reviewed on two devices offline:** both answers count after sync. The due date is recomputed from all answers, identically on both devices.
- **Card deleted on another device while being reviewed here:** after sync the entry is gone, and the answer given here is dropped (PD-17).
- **Time zone change or travel:** "today" follows the device's current time zone. Answers keep the time zone they were given in.
- **Device clock wrong:** answers are still recorded. Scheduling impact is handled in [scheduler.md](../../architecture/scheduler.md).
- **Very long sentence on a small screen:** the card scrolls; the word stays highlighted.
- **Entry has no translation:** it has no cards in review ([saving without enrichment](enrichment-unavailable.md)).
- **Thousands of due cards after import (later) or a long break:** catch-up applies.
- **Daily new-word limit set to 0:** only reviews; new words wait.

## Offline

Review works completely offline: queue, answers, scheduling, summary. Answers sync later. Due counts on two devices may differ until they sync.
