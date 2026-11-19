"""Text rules for the dictionary build.

`match_key` and `search_fold` are a port of the shared text rules (same explicit character lists as
spec/fixtures/README.md and tools/fixtures/torifix/text.py); tests run them against
spec/fixtures/normalization/*.json.
"""

import re
import unicodedata

QUOTES_SINGLE = "’‘ʼ′"  # ’ ‘ ʼ ′ → '
QUOTES_DOUBLE = "“”„″"  # “ ” „ ″ → "
DASHES = "‐‑‒–—−"  # ‐ ‑ ‒ – — − → -
SPACE_SEPARATORS = "  " + "".join(chr(c) for c in range(0x2000, 0x200B)) + "  　"
DEFAULT_IGNORABLES = "­​‌‍⁠﻿"
WHITESPACE = "\t\n\u000b\u000c\r \u0085  "

_MAP = {**{c: "'" for c in QUOTES_SINGLE}, **{c: '"' for c in QUOTES_DOUBLE},
        **{c: "-" for c in DASHES}, **{c: " " for c in SPACE_SEPARATORS}}
_TRANS = str.maketrans({**_MAP, **{c: None for c in DEFAULT_IGNORABLES}})


def _is_edge(c: str) -> bool:
    return c in WHITESPACE or unicodedata.category(c).startswith("P")


def _steps_1_to_3(s: str) -> str:
    return unicodedata.normalize("NFC", s).translate(_TRANS)


def _lower(s: str) -> str:
    # Per code point full default mapping: no locale, no context (Σ → σ, never ς).
    return "".join(c.lower() for c in s)


def collapse(s: str) -> str:
    out, pending = [], False
    for c in s:
        if c in WHITESPACE:
            pending = True
        else:
            if pending and out:
                out.append(" ")
            pending = False
            out.append(c)
    return "".join(out)


def _yo(s: str) -> str:
    return s.replace("ё", "е").replace("Ё", "Е")


def match_key(s: str) -> str:
    s = collapse(_lower(_steps_1_to_3(s)))
    start, end = 0, len(s)
    while start < end and _is_edge(s[start]):
        start += 1
    while end > start and _is_edge(s[end - 1]):
        end -= 1
    return _yo(s[start:end])


def search_fold(s: str) -> str:
    return _yo(collapse(_lower(_steps_1_to_3(s))))


# --- Cleaning source text ("normalise") ---------------------------------------------------------

_MARKUP = [
    (re.compile(r"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]"), r"\1"),  # [[target|label]] → label
    (re.compile(r"\{\{[^{}]*\}\}"), ""),                      # leftover templates
    (re.compile(r"'''?"), ""),                                # bold/italic quotes
    (re.compile(r"<[^<>]+>"), ""),                            # HTML tags
]
_STRESS = {0x0300: None, 0x0301: None}  # combining grave/acute = Russian stress marks


def clean(s: str) -> str:
    """NFC, ASCII quotes/dashes/spaces, default-ignorables removed, wiki markup stripped, whitespace collapsed."""
    s = _steps_1_to_3(s)
    for rx, repl in _MARKUP:
        s = rx.sub(repl, s)
    return collapse(s)


def clean_ru(s: str) -> str:
    """`clean` plus removal of stress accents (бе́гать → бегать); ё/й survive because only U+0300/U+0301 go."""
    s = unicodedata.normalize("NFD", s).translate(_STRESS)
    return clean(s)
