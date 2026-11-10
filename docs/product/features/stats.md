# Stats

- **Priority:** P1.
- **Status:** confirmed ([PD-8](../proposed-decisions.md#pd-8-stats)): one minimal screen, no gamification.
- **Analysis:** I6, X4, §6.4.

## Behaviour

One **Progress** screen:
- **Today:** cards reviewed, cards still due, new words introduced.
- **Vocabulary:** entries that are new, learning, known well, marked "already known", paused. Tapping a number opens the filtered list.
- **Activity:** reviews per day for the last 30 days.
- **Captured:** words added per week (last 8 weeks) and the top sources.

No XP, levels, streaks or leaderboards.

## Edge cases

- **Empty vocabulary:** the screen shows the empty state from [first run](first-run.md).
- **Reviews on several devices:** stats combine all devices after sync. Before sync each device shows what it knows.
- **Time zones:** each review counts on the day it happened in the time zone it was given in; days start at 04:00 (PD-4).
- **Deleted entries:** they and their reviews disappear from all numbers.

## Offline

Computed on the device; fully offline.
