# Export and backup

- **Priority:** P1.
- **Status:** confirmed ([PD-11](../proposed-decisions.md#pd-11-export), [PD-12](../proposed-decisions.md#pd-12-backup-for-users-without-an-account)).
- **Analysis:** A5, X2; [memory://12](memory://12) (no lock-in).

## Behaviour

**Export** (Settings → Export)
- **CSV:** one row per entry: text, translations, definitions, first sentence, source, tags, stage, created date. Opens in spreadsheets and can be imported into other apps.
- **JSON:** the complete vocabulary: all meanings, sentences, sources, tags and the full review history. This is the backup format: the user's records in the sync format ([sync.md](../../architecture/sync.md) §12), documented and versioned. CSV is a readable, lossy export, not a backup.
- The file is created on the device and handed to the share sheet (save to Files, send, AirDrop and so on).
- Available without an account.
- Both formats include the Wiktionary attribution line (CC BY-SA) when the export contains Wiktionary-derived text ([dictionary-data.md](../../architecture/dictionary-data.md) §5).

**Restore from JSON** (PD-12)
- Settings → Import Toriwords backup → pick a JSON file.
- Imported entries merge with existing ones by the [duplicate](duplicates.md) rules; review histories combine. Nothing existing is deleted.
- Summary: "Imported 340 words, 12 merged with existing." If some words in the file were deleted on this device or account after the backup was made, they are not restored, because deletion is final (PD-17). The summary says so: "3 words were deleted earlier and were not restored".
- If signed in, the result syncs as usual.

## Edge cases

- **Empty vocabulary:** export is disabled with a short note.
- **Very large vocabulary:** export shows progress and can be cancelled.
- **Importing the same backup twice:** no duplicates and no doubled history.
- **Backup from a newer app version:** imported if it has the same format major version; data this version does not understand is kept unchanged. A newer format major version is refused with "Update the app".
- **Backup from an older app version:** imported.
- **Corrupt or foreign file:** "This is not a Toriwords backup"; nothing changes.
- **CSV import:** not in v1 (Anki import later covers migration).
- **Deleted entries:** not exported.

## Offline

Fully offline.
