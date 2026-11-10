# Review

- **Priority:** P0.
- **Status:** confirmed: card types [PD-1](../proposed-decisions.md#pd-1-card-directions-and-exercise-types), grading [PD-2](../proposed-decisions.md#pd-2-grading), daily load [PD-4](../proposed-decisions.md#pd-4-daily-load-and-catch-up).
- **Analysis:** A2, A7, I2, I4, I9, §6.4, §7, §11 Q6–Q7.
- **Domain:** [Card, ReviewLog](../domain-model.md#card). Scheduling: [scheduler.md](../../architecture/scheduler.md).

## Behaviour

**Starting**
- The home screen shows how many cards are due today and a **Review** button. When nothing is due it shows the day of the next review ("Next review: tomorrow", "in 3 days"). Scheduling is by day, never by time of day.
- One queue contains everything due. Tags or sources do not split it (PD-3).

**A card** (PD-1). Every entry has both directions.
- **Recognition** (English shown, answer in Russian): the front shows the English word or phrase and its sentence with the word highlighted. Tapping the card flips it.
- **Recall** (Russian shown, produce the English): the front shows the Russian translation(s) and the sentence with the word blanked.
- The back shows the word, all its meanings (translation, definition, part of speech), IPA, the sentence with source, and a speaker button ([pronunciation](pronunciation.md)).
- If the entry has several sentences, a different one is shown each time.
- Without a sentence, the card shows only the word or translation.

**Grading** (PD-2)
- After the flip: **Forgot** and **Remembered**. Swiping left or right does the same.
- The next card appears immediately. The scheduler decides when the card is due again; the user never sees intervals or settings unless they open the entry.

**Actions on a card** (from a menu on the back): **Edit** the entry (opens the editor, returns to the same card), **I already know this** (excludes the entry, see [vocabulary management](vocabulary-management.md)), **Pause**, **Delete**.

**Session**
- New cards are mixed in among due reviews, up to the daily new-word limit (default 10).
- At most one card of an entry is shown per day; the other waits for a later day. For a new word this means its recall card is introduced the day after its recognition card. Exact rule: [scheduler.md](../../architecture/scheduler.md#11-daily-queue-and-catch-up-pd-4).
- A **Forgot** card comes back later in the same session until it is remembered once.
- Leaving the review at any point keeps every answer already given. There is no "session" to lose.
- When the queue is empty: a short summary (cards reviewed, words remembered, new words introduced). If more new words are waiting, **Learn more new words** introduces another batch of the daily limit. This only extends the current session and changes no setting.

**Daily load and catch-up** (PD-4)
- A review day starts at 04:00 local time.
- After a break, when the backlog is much larger than the user's normal daily load (computed from recent review history), the app enters **catch-up**:
  - the home screen says "Welcome back — N cards are waiting. We'll spread them over about a week.";
  - each day shows a manageable share of the backlog, most at-risk cards first, and the share shrinks as the backlog clears;
  - new words pause until catch-up ends;
  - **Review all now** shows the rest of the backlog in the current session only. It stores nothing; the next day's share is computed again from the history.
- The exact numbers (normal load, when catch-up starts and ends, the daily share) are defined only in [scheduler.md](../../architecture/scheduler.md#11-daily-queue-and-catch-up-pd-4), so every device shows the same counts.
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
