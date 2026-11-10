# Related-word suggestions

- **Priority:** P1.
- **Status:** confirmed ([PD-6](../proposed-decisions.md#pd-6-topical-suggestions)): related-word lists from Wiktionary shipped with the app, identical on both platforms, offline.
- **Analysis:** I1 (owner request, a gap among competitors), A8, §6.2, §8.7.

## Behaviour

- After saving a word, and on every entry screen, a **Related words** row shows up to 8 related English words and phrases: synonyms, related and derived terms, and common phrases containing the word ("mortgage" → "mortgage rate", "remortgage", "loan").
- Each suggestion shows its primary Russian translation and has **Add** (one tap, saves with that translation and enrichment as usual) and a tap to preview.
- Words already in the vocabulary are marked and are not offered for adding.
- The user can dismiss a suggestion. It stays hidden for the rest of the session on that device; dismissals are not saved or synced in v1.
- The same word gives the same suggestions on iOS and Android.

## Edge cases

- **No relations known for the word** (common for slang and phrases): the row is hidden.
- **All suggestions already saved:** the row says "You have all related words".
- **Added suggestion** has no sentence of its own; its source is "Suggested from '<word>'".
- **Quality expectation:** Wiktionary relations are narrower than true topics (it will not suggest "down payment" for "mortgage"). The owner accepted this (PD-6); curated topical sets are later.

## Offline

Works offline: the related-word lists ship with the app.
