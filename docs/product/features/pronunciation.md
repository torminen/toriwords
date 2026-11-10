# Pronunciation

- **Priority:** P1.
- **Status:** confirmed ([PD-5](../proposed-decisions.md#pd-5-pronunciation)): OS text-to-speech plus IPA, no recorded audio.
- **Analysis:** §8.4, §11 Q8.

## Behaviour

- A **speaker button** on the add/capture preview, the entry screen and both card sides plays the English word or phrase with the system English voice.
- Long-press (or a second button next to the sentence) plays the sentence.
- **IPA** from Wiktionary is shown under the word when available; the user can edit it.
- **Accent:** US English by default; UK English as a per-device setting.
- **Auto-play on reveal:** off by default; a setting.
- Playback follows the platform conventions for silent mode and other audio.

## Edge cases

- **No English voice for the chosen accent:** any installed English voice is used. With no English voice at all, the button is shown disabled; tapping it explains how to install a voice (on Android it opens the system voice-data installer). IPA stays visible.
- **Voices differ between iOS and Android or between devices:** acceptable.
- **Phrase with symbols or abbreviations:** read as the system voice reads it.
- **Russian translation:** not spoken in v1.

## Offline

Works offline with an installed system voice. IPA is stored on the entry and is available offline.
