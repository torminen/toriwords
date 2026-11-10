# Organisation (tags)

- **Priority:** P1.
- **Status:** confirmed ([PD-3](../proposed-decisions.md#pd-3-organisation)): flat tags plus filtering by source, no decks.
- **Analysis:** I2, X6, §6.4.
- **Domain:** [Tag](../domain-model.md#tag), [Source](../domain-model.md#source).

## Behaviour

- An entry can have any number of tags. Tags are optional; nothing asks for them.
- Tags are added on the add screen, in the capture sheet (collapsed by default) and on the entry screen. Typing suggests existing tags; a new name creates a tag.
- The capture sheet remembers the last used tags for 30 minutes, like the source title.
- The vocabulary list filters by one or more tags and by source ("all words from this article").
- Settings → Tags lists tags with entry counts: rename, merge (by renaming to an existing name), delete.
- Review is always one queue. Reviewing only one tag is later.

## Edge cases

- **Tag names differing only in case or spaces** ("Work", "work "): the same tag.
- **Renaming a tag to an existing name:** the two tags merge after confirmation.
- **Deleting a tag:** removes it from entries; entries stay.
- **Same tag created on two devices offline:** one tag after sync.
- **Source with no title** (URL only): shown by its domain name.

## Offline

Fully offline; tags sync.
