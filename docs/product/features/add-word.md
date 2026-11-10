# Add a word by typing

- **Priority:** P0.
- **Status:** typing with autocomplete and auto-filled translation and definition is confirmed (owner input 2). How the suggestions are presented, the base-form suggestion ([PD-14](../proposed-decisions.md#pd-14-base-form-at-capture)) and capture-time help ([PD-19](../proposed-decisions.md#pd-19-capture-time-help)) are confirmed.
- **Analysis:** A1, A6, A13, §6.3, §8.4, §11 Q1.
- **Domain:** [Entry, Sense, Context](../domain-model.md).

## Behaviour

1. An **Add** button is always reachable from the home screen and the vocabulary list. It opens the add screen with the keyboard up.
2. The user types English. After the first two characters, an **autocomplete** list shows matching English words and phrases from the dictionary. Entries already in the vocabulary are listed first and marked "In your vocabulary". Tapping one of those opens the existing entry instead.
3. When the user picks a suggestion, or confirms their own text, the screen shows a **preview**:
   - **Translation variants** in Russian, grouped by part of speech: Wiktionary translations first, then the on-device machine translation labelled "Machine translation". The first variant is preselected. The user can select several, deselect, or type their own.
   - **English definition(s)** from Wiktionary for the selected meanings, if any. The definition is in English; translations are in Russian.
   - **IPA** pronunciation from Wiktionary, if any.
   - An optional **sentence** field (where the user met the word) and an optional **source** title (for example "The Bear S2E3"). When a sentence is present, its machine translation is shown as context help, not saved (PD-19).
   - Tags (PD-3).
4. **Save** creates the entry with the chosen meanings. Each chosen variant becomes a separate meaning (Sense). Variants that were not chosen are discarded.
5. Every field in the preview is editable before saving. A field the user edits is never changed by enrichment later.
6. After saving, the screen confirms ("Saved") and clears for the next word, so several words can be added in a row. Related-word suggestions may appear ([topical suggestions](topical-suggestions.md)).
7. A new entry first appears in review according to the daily new-word limit ([review](review.md)).
8. **Base form (PD-14, P1):** if the typed word is an inflected form ("took"), the preview offers the base form ("take") as the saved text, keeping the typed form as an option.

## Edge cases

- **Word already saved:** the duplicate rules apply ([duplicates](duplicates.md)). The preview shows "Already in your vocabulary" with the existing meanings. Save adds any new meaning or sentence to the existing entry.
- **Not in the dictionary** (slang, names, new words, most phrases): no autocomplete match. The preview shows the machine translation only. If there is none either, the user types a translation ([saving without enrichment](enrichment-unavailable.md)).
- **Several meanings** ("bank"): all Wiktionary meanings are listed with their part of speech, so the user can pick the one they met.
- **Machine translation equals a Wiktionary variant:** shown once.
- **Different suggestions on iOS and Android:** acceptable (owner input 3). What the user saves is what syncs.
- **Russian typed in the field:** the app offers English candidates for the Russian text from the dictionary ("how do I say …"). Picking one continues as usual. If there are none, it says "Type the English word or phrase". ([PD-19](../proposed-decisions.md#pd-19-capture-time-help))
- **Text with only spaces or punctuation:** Save is disabled.
- **Text that looks like a sentence:** the same rule as in capture (more than 6 words, or ending with sentence punctuation; exact rule in [capture-and-extensions.md](../../architecture/capture-and-extensions.md) §2). The app offers to save it as the sentence and pick the word or phrase inside it, as in [capture](capture-share-selection.md).
- **Leaving the screen with unsaved input:** the app asks whether to discard it.

## Offline

- Saving always works offline.
- Autocomplete, Wiktionary translations, definitions and IPA work offline from first launch: the dictionary is bundled with the app ([dictionary-data.md](../../architecture/dictionary-data.md) §4; about 25 MB of app size, accepted by the owner).
- Machine translation works offline once the OS translation language data is on the device. Before that, the preview says the machine translation is unavailable ([first run](first-run.md) describes the download).
- If no suggestions are available, the user can type a translation or save without one; the entry is enriched later ([saving without enrichment](enrichment-unavailable.md)).
