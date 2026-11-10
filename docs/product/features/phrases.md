# Phrases as first-class items

- **Priority:** P0.
- **Status:** proposed.
- **Analysis:** A3, §6.1.
- **Domain:** [Entry](../domain-model.md#entry) (`kind` is derived).

## Behaviour

- A phrase (phrasal verb, idiom, collocation, any multi-word expression: "take off", "on the fence", "make ends meet") is saved, listed, searched, reviewed and synced exactly like a single word.
- Whether an entry is a word or a phrase is decided automatically: more than one word means phrase. The user never chooses it.
- In capture, the user picks a phrase by tapping several adjacent words in the sentence ([capture](capture-share-selection.md)).
- Translation of a phrase uses Wiktionary when it lists the phrase (many idioms and phrasal verbs are listed), otherwise machine translation.
- The vocabulary list can be filtered to **Phrases**.
- In review, the highlight or blank in the sentence covers the whole phrase as it appeared.

## Edge cases

- **Separable phrasal verbs** ("take your shoes off" for "take off"): the user picks the non-adjacent words; v1 only supports adjacent words in capture. The user picks "take" and edits the text to "take off", or types it. The sentence is still kept; the highlight covers the picked word only.
- **Phrase containing a saved word** ("take off" while "take" is saved): separate entries, no link between them in v1.
- **Very long phrase** (over 8 words): allowed, with the "looks like a sentence" warning from [add word](add-word.md).
- **Phrase with a placeholder** ("one's", "someone", "sth"): saved as typed; no special handling in v1.
- **Machine translation of an idiom is literal:** expected; the user picks or types the right meaning. This is why variants are shown (A6).

## Offline

Same as single words.
