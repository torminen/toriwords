# Vocabulary management

- **Priority:** P0 (bulk actions P1).
- **Status:** proposed. Deletion recovery pending [PD-15](../proposed-decisions.md#pd-15-deletion-recovery); delete-vs-edit across devices pending [PD-17](../proposed-decisions.md#pd-17-edit-on-one-device-vs-delete-on-another).
- **Analysis:** X2, §6.4.
- **Domain:** [Entry states](../domain-model.md#entry), [Sense](../domain-model.md#sense), [Context](../domain-model.md#context).

## Behaviour

**List**
- All entries, newest first. Each row: the word or phrase, the primary translation, and a small stage marker (new / learning / known well / known / paused).
- Sort: newest, A–Z, next due.
- Filters: stage, **Needs translation**, **Check translation**, **Phrases**, tag (PD-3), source.

**Search**
- One search field finds entries by English text, Russian translation, definition and sentence text. Case and typographic variants are ignored; Russian "ё" matches "е".
- Results update as the user types.

**Entry screen**
- Word or phrase, IPA, speaker button.
- Meanings in order, each with translation, definition and part of speech. Reorder, add, edit, delete.
- Sentences, each with its source; tapping a web source opens the page.
- Tags, note.
- Learning: stage and "Next review: in 3 days" per card direction. No intervals or scheduler numbers.
- Related words ([topical suggestions](topical-suggestions.md)).

**Actions**
- **Edit** any field. Editing the text to match another entry offers a merge ([duplicates](duplicates.md)).
- **I already know this:** the entry leaves review, stays in the list as "known", and counts as known in stats.
- **Pause:** the entry leaves review and stays in the list as "paused".
- **Resume learning:** continues from the existing history.
- **Delete:** confirmation, then (pending PD-15) a short **Undo**. Deleted entries are gone on all devices with their history; this cannot be reversed after the undo window. Deletion is terminal (pending PD-17).
- **Bulk (P1):** multi-select in the list to delete, tag, mark known or pause.

## Edge cases

- **Deleting the last meaning:** allowed. The entry moves to "Needs translation".
- **Editing the text of a reviewed entry:** history is kept (the user probably fixed a typo).
- **Deleting a sentence used by the highlight in a card:** the card falls back to another sentence or none.
- **Entry deleted on another device while open here:** after sync the screen closes with "This word was deleted on another device".
- **Search with no results:** offers "Add '…'" with the search text.
- **Large vocabulary** (10,000+ entries): the list and search stay responsive.

## Offline

Everything works offline. Changes sync later.
