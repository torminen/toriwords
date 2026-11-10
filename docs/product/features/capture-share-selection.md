# Capture via Share / text selection

- **Priority:** P0.
- **Status:** confirmed (owner input 2). Details of the capture sheet are proposed.
- **Analysis:** A1, A2, A9, I3, §6.1, §8.3, X9.
- **Domain:** [Entry, Context, Source](../domain-model.md), [enrichment](../domain-model.md#enrichment).

## Behaviour

**Entry points**
- **Android:** select text in any app → **Toriwords** in the selection toolbar. Or share text or a link to Toriwords from any app's share menu.
- **iOS:** select text → **Share** → **Toriwords**. Or share text or a link from any app's share menu.
- Both open a compact **capture sheet** over the current app. The user stays in the app they were reading or watching.

**Capture sheet**
1. **Short selection** (up to 6 words): the selection becomes the word or phrase to save. The sentence field is empty; the user can paste or type the sentence.
2. **Longer selection** (more than 6 words, or ending with sentence punctuation): the selection is treated as the sentence. The words are shown as tappable chips. The user taps one word, or several adjacent words for a phrase, to choose what to save. The sentence is kept as context with the chosen word highlighted.
3. **Shared link** (URL only, no text): the URL and page title are stored as the source. The user types the word.
4. **Source:** when the share includes a URL and title, they are saved as the source. On Android the app name is saved when the OS provides it. The user can type or edit a source title (for example "The Bear S2E3"). The last used source title is offered again for 30 minutes, so a series session does not need retyping.
5. **Translation:** the sheet shows the translation and lets the user pick variants as in [add word](add-word.md) **when the platform allows enrichment inside the sheet**. Where it does not (the iOS Share Extension in v1), the sheet saves the raw capture: text, sentence and source, plus a translation if the user typed one. The entry is marked *pending enrichment*, and the app fills in the translation, definition and IPA the next time it runs ([enrichment.md](../../architecture/enrichment.md)).
6. **Save** closes the sheet and returns to the source app with a short confirmation. Total target: two taps after the selection for a short selection.
7. Entries enriched automatically after capture (not chosen by the user) appear in the vocabulary list filter **"Check translation"** until the user opens them or reviews them once, so wrong automatic meanings can be fixed.

## Edge cases

- **Word already saved:** the sheet shows "Already in your vocabulary". Save attaches the new sentence and source to the existing entry ([duplicates](duplicates.md)).
- **Selection is Russian or another script:** the sheet says "Toriwords saves English words and phrases" and lets the user edit the text. Save stays disabled until the text contains Latin letters.
- **Selection spans several sentences:** after the user picks the word, only the sentence that contains it is kept.
- **Sentence longer than 500 characters:** it is cut to 500 characters around the chosen word, at word boundaries, with "…" marks.
- **Very large share** (more than 5,000 characters, for example a whole article): only the first 5,000 characters are shown for picking. The URL, if present, is still saved as the source.
- **Selection with line breaks, extra spaces or subtitle markup** (for example `<i>`, `[music]`, speaker names before a colon): these are cleaned for display. The chosen text follows the [duplicate](duplicates.md) normalisation.
- **Word chosen is an inflected form** ("took off"): saved as chosen; the highlight marks it in the sentence. Base form is pending PD-14.
- **App never opened before:** capture still works. The app finishes first-run setup the next time it opens.
- **The user dismisses the sheet:** nothing is saved.
- **Streaming apps:** text selection does not work in most video players. The spec does not promise capture from Netflix/YouTube subtitles on the phone (X9). The user types the word instead, or uses OCR when it arrives (later).

## Offline

- Capture never needs the network and never waits for it. Saving is instant.
- Enrichment of pending captures happens when the app runs and its sources are available. Until then the entry is in the vocabulary list with "Translation pending" and is not reviewed ([saving without enrichment](enrichment-unavailable.md)).
