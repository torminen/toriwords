# First run and empty states

- **Priority:** P0.
- **Status:** confirmed.
- **Analysis:** X1, X6, §6.4.

## Behaviour

**First launch**
- No account screen, no onboarding carousel, no language-pair choice (v1 is RU → EN). The app opens on the home screen.
- The home screen's empty state explains the three ways to add words, with the platform's actual steps:
  - **Type:** the Add button.
  - **From any app (Android):** select text → Toriwords.
  - **From any app (iOS):** select text → Share → Toriwords. On iOS, a one-time tip shows how to move Toriwords to the front of the share menu.
- **Add your first word** opens the add screen.
- **Dictionary:** bundled with the app, available offline from the first launch.
- **Machine translation data:**
  - Android: the app downloads the English–Russian model (about 30 MB) automatically on Wi-Fi after first launch; on mobile data the user can start it from Settings → Translation.
  - iOS: the system asks the user to download the language data the first time translation is needed online.
  - Until it is there, or if the user declines, the app uses the dictionary only, and Settings → Translation offers the download again.
- Notifications are not requested at first launch ([reminders](reminders-widget.md)).

**Empty states elsewhere**
- **Review, nothing added yet:** "Add words to start reviewing" with the Add button.
- **Review, all done:** "All done for today. Next review: tomorrow" (or "in 3 days"; always a day, never a time), plus **Learn more new words** when new words are waiting.
- **Words added but none reviewable** (all without translation): points to the "Needs translation" filter.
- **Search with no results:** offers to add the search text.

## Edge cases

- **First use is a capture from another app** (the app was installed but never opened): capture works and saves the word, sentence and source.
  - Android: the capture runs inside the app, so the dictionary is available as usual.
  - iOS: the share extension can use the dictionary only after the app has been opened once ([dictionary-data.md](../../architecture/dictionary-data.md) §4). Before that, the capture is saved *pending enrichment*, and the meaning is filled in, flagged "Check translation", on first open.
  - First-run setup completes silently on first open.
- **Reinstall with an account:** the empty state also shows "Have an account? Sign in to restore your words" in a single line, without blocking.
- **Device language neither English nor Russian:** the app opens in English.

## Offline

First run works fully offline. Only the translation download needs the network and waits for it.
