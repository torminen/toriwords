# First run and empty states

- **Priority:** P0.
- **Status:** proposed.
- **Analysis:** X1, X6, §6.4.

## Behaviour

**First launch**
- No account screen, no onboarding carousel, no language-pair choice (v1 is RU → EN). The app opens on the home screen.
- The home screen's empty state explains the three ways to add words, with the platform's actual steps:
  - **Type:** the Add button.
  - **From any app (Android):** select text → Toriwords.
  - **From any app (iOS):** select text → Share → Toriwords. On iOS, a one-time tip shows how to move Toriwords to the front of the share menu.
- **Add your first word** opens the add screen.
- **Translation download:** if on-device translation RU ↔ EN is not installed, the app offers to download it the first time it is needed and the device is online. If declined, the app uses Wiktionary only; Settings → Translation offers the download again.
- Notifications are not requested at first launch ([reminders](reminders-widget.md)).

**Empty states elsewhere**
- **Review, nothing added yet:** "Add words to start reviewing" with the Add button.
- **Review, all done:** "All done for today. Next review: tomorrow at 09:12", plus **Learn more new words** when new words are waiting.
- **Words added but none reviewable** (all without translation): points to the "Needs translation" filter.
- **Search with no results:** offers to add the search text.

## Edge cases

- **First use is a capture from another app** (the app was installed but never opened): capture works; first-run setup completes silently on first open.
- **Reinstall with an account:** the empty state also shows "Have an account? Sign in to restore your words" in a single line, without blocking.
- **Device language neither English nor Russian:** the app opens in English.

## Offline

First run works fully offline. Only the translation download needs the network and waits for it.
