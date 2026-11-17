"""Capture text rules, doc 36 §5.2. Lengths and cuts count Unicode code points;
highlight offsets/lengths are UTF-16 code units of the stored sentence."""

import re
import unicodedata

from .text import SPACE_SEPARATORS, WHITESPACE, collapse, is_punct, is_ws, match_key

MAX_CHARS = 5000
MAX_SENTENCE = 500
SENTENCE_WORDS = 6
TERMINALS = ".!?…"
CLOSERS = "\"'”’»)]"
ELLIPSIS = "…"

_TAG = re.compile(r"<[^<>]*>")
# "Space" for speaker labels: WHITESPACE plus the Zs space separators (explicit lists, see text.py).
_SP = re.escape(WHITESPACE + SPACE_SEPARATORS)
_SPEAKER = re.compile(rf"^[ \t]*(?:[^{_SP}:]+[ \t]+){{0,2}}[^{_SP}:]+:(?=[{_SP}]|$)[ \t]*")
_LINE_BREAK = re.compile(r"\r\n|\r|\n")


def utf16_len(s: str) -> int:
    return sum(2 if ord(c) > 0xFFFF else 1 for c in s)


def is_latin_letter(c: str) -> bool:
    o = ord(c)
    return ("A" <= c <= "Z" or "a" <= c <= "z"
            or (0x00C0 <= o <= 0x024F and o not in (0x00D7, 0x00F7))
            or 0x1E00 <= o <= 0x1EFF)


def _strip_annotations(text: str) -> str:
    """Removes [..] and (..) whose content is one or more letters (general category L*) or U+0020.
    Left-to-right scan; a removed span is not rescanned (same as a regex substitution)."""
    out, i, n = [], 0, len(text)
    while i < n:
        close = {"[": "]", "(": ")"}.get(text[i])
        if close:
            j = i + 1
            while j < n and (text[j] == " " or unicodedata.category(text[j]).startswith("L")):
                j += 1
            if j > i + 1 and j < n and text[j] == close:
                i = j + 1
                continue
        out.append(text[i])
        i += 1
    return "".join(out)


def clean(text: str) -> tuple[str, list[int]]:
    """Returns the cleaned text and the positions where a line break joined two lines."""
    text = _TAG.sub("", text)
    text = _strip_annotations(text)
    lines = [collapse(_SPEAKER.sub("", line)) for line in _LINE_BREAK.split(text)]
    out, breaks = "", []
    for line in lines:
        if not line:
            continue
        if out:
            breaks.append(len(out) + 1)  # sentence boundary before this line
            out += " "
        out += line
    out = collapse(out[:MAX_CHARS])
    return out, [b for b in breaks if b < len(out)]


def _ends_sentence(s: str, end: int) -> bool:
    """True if s[:end] ends with a terminal followed by optional closers."""
    i = end
    while i > 0 and s[i - 1] in CLOSERS:
        i -= 1
    return i > 0 and s[i - 1] in TERMINALS


def classify(cleaned: str) -> str:
    words = cleaned.split(" ") if cleaned else []
    return "sentence" if len(words) > SENTENCE_WORDS or _ends_sentence(cleaned, len(cleaned)) else "term"


def saveable(cleaned: str) -> bool:
    return any(is_latin_letter(c) for c in cleaned)


def chips(cleaned: str) -> list[tuple[int, int]]:
    """Word chips: whitespace tokens with leading/trailing punctuation stripped; empty ones dropped."""
    out, pos = [], 0
    for token in cleaned.split(" "):
        s, e = pos, pos + len(token)
        while s < e and is_punct(cleaned[s]):
            s += 1
        while e > s and is_punct(cleaned[e - 1]):
            e -= 1
        if s < e:
            out.append((s, e))
        pos += len(token) + 1
    return out


def _boundaries(cleaned: str, breaks: list[int]) -> list[int]:
    """Start positions of sentences (besides 0)."""
    starts = set(breaks)
    for i, c in enumerate(cleaned):
        if c == " " and _ends_sentence(cleaned, i):
            starts.add(i + 1)
    return sorted(starts)


def extract(text: str, first_chip: int, last_chip: int) -> dict:
    cleaned, breaks = clean(text)
    cs = chips(cleaned)
    span_s, span_e = cs[first_chip][0], cs[last_chip][1]
    starts = [0] + _boundaries(cleaned, breaks)
    sent_s = max(b for b in starts if b <= span_s)
    later = [b for b in starts if b >= span_e]
    sent_e = (min(later) if later else len(cleaned))
    sentence = cleaned[sent_s:sent_e].rstrip(WHITESPACE)
    hl_s, hl_e = span_s - sent_s, span_e - sent_s
    if len(sentence) > MAX_SENTENCE:
        sentence, hl_s, hl_e = _cut(sentence, hl_s, hl_e)
    return {"entryText": cleaned[span_s:span_e], "sentence": sentence,
            "highlight": {"offset": utf16_len(sentence[:hl_s]), "length": utf16_len(sentence[hl_s:hl_e])}}


def _cut(sentence: str, hl_s: int, hl_e: int) -> tuple[str, int, int]:
    """Cut to ≤ 500 code points around the span at word boundaries, marking cuts with '…'.
    Grows one word to the left, then one to the right, while the result still fits."""
    words, pos = [], 0
    for token in sentence.split(" "):
        words.append((pos, pos + len(token)))
        pos += len(token) + 1
    first = next(i for i, (s, e) in enumerate(words) if e > hl_s)
    last = next(i for i, (s, e) in reversed(list(enumerate(words))) if s < hl_e)

    def render(a: int, b: int) -> tuple[str, int]:
        prefix = "" if a == 0 else ELLIPSIS
        suffix = "" if b == len(words) - 1 else ELLIPSIS
        body = sentence[words[a][0]:words[b][1]]
        return prefix + body + suffix, len(prefix) - words[a][0]

    a, b = first, last
    grew = True
    while grew:
        grew = False
        if a > 0 and len(render(a - 1, b)[0]) <= MAX_SENTENCE:
            a, grew = a - 1, True
        if b < len(words) - 1 and len(render(a, b + 1)[0]) <= MAX_SENTENCE:
            b, grew = b + 1, True
    out, shift = render(a, b)
    return out, hl_s + shift, hl_e + shift


def _is_word_char(c: str) -> bool:
    return unicodedata.category(c)[0] in "LN"


def typed_highlight(sentence: str, entry_text: str) -> dict | None:
    """§5.2 item 6: first occurrence of the Entry text at word boundaries, match-key folded."""
    key = match_key(entry_text)
    if not key:
        return None
    n = len(sentence)
    for s in range(n):
        if not _is_word_char(sentence[s]) or (s > 0 and _is_word_char(sentence[s - 1])):
            continue
        for e in range(s + 1, n + 1):
            if not _is_word_char(sentence[e - 1]) or (e < n and _is_word_char(sentence[e])):
                continue
            if match_key(sentence[s:e]) == key:
                return {"offset": utf16_len(sentence[:s]), "length": utf16_len(sentence[s:e])}
    return None
