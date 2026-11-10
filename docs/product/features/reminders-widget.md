# Reminders and widget

- **Priority:** P1.
- **Status:** pending [PD-7](../proposed-decisions.md#pd-7-reminders-and-widget). The behaviour below follows the recommendation: one opt-in daily local reminder, a due-count widget, no streaks.
- **Analysis:** A11, X4, X11, §8.5.

## Behaviour

**Reminder**
- Off by default. After the user finishes their first review session, the app offers once: "Remind you to review every day?" with a time picker (default 19:00). Also available in Settings.
- Turning it on asks for notification permission at that moment, not at first launch.
- One notification per day at the chosen time, only if cards are due: "12 words to review". Tapping it opens review.
- No notification on days with nothing due, and none if the user already reviewed everything due today.
- Only local notifications computed on the device. No push server.

**Widget**
- Home-screen widget with today's due count and the next due time when nothing is due. Tapping opens review.
- Lock-screen variant where the OS supports it.
- The count updates after reviewing, after sync, and at day start.

## Edge cases

- **Notification permission denied:** Settings shows "Notifications are off for Toriwords" with a link to system settings. The app does not ask again by itself.
- **Reviews done on another device:** the count is right after sync. Before sync, the reminder may show a count that was already reviewed elsewhere; this is acceptable.
- **Time zone change:** the reminder fires at the chosen local time in the new zone.
- **Reminder time per device:** each device has its own (PD-16).
- **Catch-up mode:** the count shows today's share, not the whole backlog.
- **App not opened for a long time:** the OS may limit background updates. The widget and reminder show the best known count; opening the app refreshes them.

## Offline

Fully offline.
