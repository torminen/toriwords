# Duplicates

- **Priority:** P0.
- **Status:** proposed.
- **Analysis:** A2, I7.
- **Domain:** [Duplicates](../domain-model.md#duplicates). Normalisation fixtures: [parity-testing.md](../../architecture/parity-testing.md).

## Behaviour

- The vocabulary never contains the same word or phrase twice. "Same" means equal after normalisation: case, surrounding punctuation, extra spaces and typographic apostrophes, quotes and dashes are ignored. "Mortgage", "mortgage." and " mortgage " are the same. "Don't" and "don’t" are the same.
- Inflections and spelling variants are different words: "run" and "ran", "colour" and "color". (Base-form suggestion at capture is pending PD-14.)
- **Repeat capture or repeat add** of an existing word:
  - the user is told "Already in your vocabulary" before saving, with the existing meanings shown;
  - the new sentence and source are added to the existing entry, unless that exact sentence from that source is already there;
  - a chosen translation becomes a new meaning only if the entry does not have it already;
  - learning progress is kept. The entry's review schedule does not change.
- **Editing the text** of an entry to match another entry: the app says "'X' is already in your vocabulary" and offers **Merge** or **Cancel**. Merging combines meanings, sentences, tags and review history.
- **Same word saved on two devices** before they synced: after sync there is one entry with all meanings, sentences and the review history of both. The user is not asked anything.

## Edge cases

- **Repeat capture of an excluded word** ("already known" or paused): the sentence is added. The app shows "You marked this as known" with a **Resume learning** action. It does not resume automatically.
- **Repeat capture of a deleted word:** a deleted word is gone; saving it creates a fresh entry with no history ([vocabulary management](vocabulary-management.md)).
- **Different capitalisation matters to the user** ("US" vs "us"): they are treated as the same entry in v1. The user can add both meanings to the one entry.
- **Merging two entries whose meanings overlap:** identical meanings appear once; their order follows the earlier-created entry.
- **The same word as a word and inside a phrase** ("take" and "take off"): different entries.

## Offline

All duplicate checks run on the device and work offline. Duplicates created on different devices while offline are merged on the next sync, without asking the user.
