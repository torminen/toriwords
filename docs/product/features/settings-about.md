# Settings and about

- **Priority:** P0.
- **Status:** UI in English and Russian is confirmed (owner input 4). The settings list is proposed; which settings sync is pending [PD-16](../proposed-decisions.md#pd-16-which-settings-sync).
- **Analysis:** X6; [memory://12](memory://12) (attribution, open source).

## Behaviour

Settings are short; the defaults are meant to be right for most people (X6).

| Section | Settings | Default | Synced (PD-16) |
|---|---|---|---|
| Learning | New words per day (0–50) | 10 | yes |
| Learning | Day starts at | 04:00 | yes |
| Reminders | Daily reminder on/off, time ([reminders](reminders-widget.md)) | off, 19:00 | no |
| Pronunciation | Auto-play on card reveal | off | no |
| Translation | On-device translation status and download; Wiktionary data status | — | no |
| Language | App language: System / English / Русский | System | no |
| Account | Sign in, status, sign out, delete account ([account and sync](account-sync.md)) | — | — |
| Data | Export, restore ([export](export.md)), Tags ([organisation](organisation.md)) | — | — |
| About | Version, source code link, licences, attribution, privacy | — | — |

**App language**
- Follows the system language when it is Russian or English, otherwise English.
- Can be overridden per app, using the platform's per-app language setting where it exists.
- Changes the interface only. Words, sentences and translations are never translated.

**About and licences**
- App version and a link to the open-source repository.
- **Wiktionary attribution:** "Dictionary data from Wiktionary, available under CC BY-SA", with a link to the licence and the source. Entries whose data came from Wiktionary show a small "Wiktionary" mark on the entry screen, linking to the same attribution.
- Licences of all bundled data and open-source libraries.
- A short privacy statement: what is stored on the device, what syncs when signed in, and that nothing else is collected (open question 3 in the [README](../README.md#open-questions-for-the-owner)).

## Edge cases

- **System language changes** while "System" is selected: the app follows on next launch.
- **Lowering the new-word limit** mid-day below what was already introduced: no more new words today; nothing is taken back.
- **Changing the day start:** applies from the next day.
- **Settings changed on two devices:** synced settings follow the most recent change.

## Offline

All settings work offline, except downloading translation data, which needs the network once.
