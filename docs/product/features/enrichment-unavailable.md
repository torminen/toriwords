# Saving without enrichment

- **Priority:** P0.
- **Status:** confirmed.
- **Analysis:** A4, A13, §8.4, §11 Q1; [memory://8](memory://8) (network never required to add words).
- **Domain:** [Enrichment](../domain-model.md#enrichment).

## Behaviour

Translation and definition suggestions can be missing:
- the word is not in Wiktionary, or Wiktionary has no Russian translation for it;
- the OS translation language pack is not downloaded and the device is offline;
- the capture came from the iOS share sheet without a dictionary hit: machine translation is not available there and is added when the app next runs ([capture](capture-share-selection.md)).

In all these cases:
1. The user can **always save**. They can type a translation themselves, or save with none.
2. An entry without a translation is shown in the vocabulary list as **"No translation yet"** and is listed under the **"Needs translation"** filter. It is not reviewed until it has a translation, because a card without an answer is useless.
3. **Pending** entries (no attempt yet, or sources unavailable) are enriched automatically when the sources become available: when the app opens, after the translation pack is downloaded, or when the device comes online if enrichment needs it.
4. Enrichment **only fills empty fields**. It never replaces what the user typed or edited.
5. If enrichment ran and found nothing, the entry shows **"No translation found — add your own"**. The entry screen has a **Try again** action, and the app also retries by itself when a new source becomes available (for example after the machine translation data is downloaded, or on another device).
6. When enrichment fills a translation the user did not choose, the entry goes into the **"Check translation"** filter ([capture](capture-share-selection.md)).

## Edge cases

- **User types a translation, enrichment later finds more:** the typed translation stays as the only meaning. Wiktionary and machine variants are offered on the entry screen as **"Suggested meanings"** for one-tap adding. They are not added automatically.
- **User deletes an auto-filled translation:** the field stays empty; enrichment does not refill a field the user cleared. The entry moves to "Needs translation".
- **Enrichment runs on two devices for the same pending entry:** the result is the same entry with one set of meanings ([duplicates](duplicates.md); mechanism in [enrichment.md](../../architecture/enrichment.md) §4).
- **Translation pack download refused or failing:** the app keeps working with Wiktionary only and says so in Settings → Translation.
- **Many pending entries** (for example 30 captures in a share extension session): they are enriched in the background without blocking the user. The list shows progress.

## Offline

This feature exists for offline use. Saving is always offline. Enrichment that needs the network or a download waits for it and retries silently.
