# Export and backup

- **Priority:** P1.
- **Status:** pending [PD-11](../proposed-decisions.md#pd-11-export) and [PD-12](../proposed-decisions.md#pd-12-backup-for-users-without-an-account).
- **Analysis:** A5, X2; [memory://12](memory://12) (no lock-in).

## Behaviour

**Export** (Settings → Export)
- **CSV:** one row per entry: text, translations, definitions, first sentence, source, tags, stage, created date. Opens in spreadsheets and can be imported into other apps.
- **JSON:** the complete vocabulary: all meanings, sentences, sources, tags and the full review history. Documented format, versioned.
- The file is created on the device and handed to the share sheet (save to Files, send, AirDrop and so on).
- Available without an account.

**Restore from JSON** (PD-12)
- Settings → Import Toriwords backup → pick a JSON file.
- Imported entries merge with existing ones by the [duplicate](duplicates.md) rules; review histories combine. Nothing existing is deleted.
- Summary: "Imported 340 words, 12 merged with existing."
- If signed in, the result syncs as usual.

## Edge cases

- **Empty vocabulary:** export is disabled with a short note.
- **Very large vocabulary:** export shows progress and can be cancelled.
- **Importing the same backup twice:** no duplicates and no doubled history.
- **Backup from a newer app version:** the app asks to update first.
- **Backup from an older app version:** imported.
- **Corrupt or foreign file:** "This is not a Toriwords backup"; nothing changes.
- **CSV import:** not in v1 (Anki import later covers migration).
- **Deleted entries:** not exported.

## Offline

Fully offline.
