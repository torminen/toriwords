"""Text keys. Character sets are explicit lists (see fixtures/README.md)."""

import unicodedata

QUOTES_SINGLE = "’‘ʼ′"  # ’ ‘ ʼ ′ → '
QUOTES_DOUBLE = "“”„″"  # “ ” „ ″ → "
DASHES = "‐‑‒–—−"  # ‐ ‑ ‒ – — − → -
# Space separators (Zs) other than U+0020 → U+0020.
SPACE_SEPARATORS = "               　"
# Removed outright: soft hyphen, ZWSP, ZWNJ, ZWJ, word joiner, BOM.
DEFAULT_IGNORABLES = "­​‌‍⁠﻿"
# Whitespace for collapse/trim/tokenising: U+0009–U+000D, U+0020, U+0085, U+2028, U+2029
# (after the space-separator mapping every Zs is already U+0020).
WHITESPACE = "\t\n\u000b\u000c\r \u0085  "

_MAP = {**{c: "'" for c in QUOTES_SINGLE}, **{c: '"' for c in QUOTES_DOUBLE},
        **{c: "-" for c in DASHES}, **{c: " " for c in SPACE_SEPARATORS}}


def is_ws(c: str) -> bool:
    return c in WHITESPACE


def is_punct(c: str) -> bool:
    return unicodedata.category(c).startswith("P")


def _steps_1_to_3(s: str) -> str:
    s = unicodedata.normalize("NFC", s)
    s = "".join(_MAP.get(c, c) for c in s)
    return "".join(c for c in s if c not in DEFAULT_IGNORABLES)


def lower(s: str) -> str:
    # Per code point full default lowercase mapping: no locale, no context (Σ → σ, never ς).
    return "".join(c.lower() for c in s)


def collapse(s: str) -> str:
    out, pending = [], False
    for c in s:
        if is_ws(c):
            pending = True
        else:
            if pending and out:
                out.append(" ")
            pending = False
            out.append(c)
    return "".join(out)


def yo(s: str) -> str:
    return s.replace("ё", "е").replace("Ё", "Е")


def match_key(s: str) -> str:
    s = collapse(lower(_steps_1_to_3(s)))
    start, end = 0, len(s)
    while start < end and (is_punct(s[start]) or is_ws(s[start])):
        start += 1
    while end > start and (is_punct(s[end - 1]) or is_ws(s[end - 1])):
        end -= 1
    return yo(s[start:end])


translation_key = match_key


def sentence_key(s: str) -> str:
    return yo(collapse(_steps_1_to_3(s)))


def tag_key(s: str) -> str:
    return yo(collapse(lower(unicodedata.normalize("NFC", s))))


def search_fold(s: str) -> str:
    return yo(collapse(lower(_steps_1_to_3(s))))


def source_key(title: str | None, app: str | None, kind: str) -> dict:
    """Natural key of a Source without URL: matchKey(title), app as stored, suggested flag."""
    return {"title": match_key(title or ""), "app": app, "suggested": kind == "suggested"}


# --- URL key -------------------------------------------------------------------------------------

TRACKING_PARAMS = {"fbclid", "gclid", "yclid", "mc_eid"}
DEFAULT_PORTS = {"http": "80", "https": "443"}


def _punycode_host(host: str) -> str:
    labels = []
    for label in host.split("."):
        if all(ord(c) < 0x80 for c in label):
            labels.append(label)
        else:
            labels.append("xn--" + label.encode("punycode").decode("ascii"))
    return ".".join(labels)


def url_key(url: str) -> str:
    """Explicit split, no platform URL parser: scheme ':' '//' authority path ['?' query] ['#' fragment]."""
    s = unicodedata.normalize("NFC", url)
    s = s.strip(WHITESPACE)
    colon = s.find(":")
    scheme = s[:colon].lower() if colon > 0 else ""
    if scheme not in DEFAULT_PORTS or not s[colon + 1:].startswith("//"):
        return s
    rest = s[colon + 3:]
    hash_at = rest.find("#")
    if hash_at >= 0:
        rest = rest[:hash_at]
    query = None
    q_at = rest.find("?")
    if q_at >= 0:
        rest, query = rest[:q_at], rest[q_at + 1:]
    slash = rest.find("/")
    authority, path = (rest, "") if slash < 0 else (rest[:slash], rest[slash:])
    userinfo = ""
    at = authority.rfind("@")
    if at >= 0:
        userinfo, authority = authority[:at + 1], authority[at + 1:]
    host, port = authority, None
    if not host.startswith("[") and ":" in host:
        host, port = host.rsplit(":", 1)
    host = _punycode_host(lower(host))
    if port is not None and (port == "" or port == DEFAULT_PORTS[scheme]):
        port = None
    out = f"{scheme}://{userinfo}{host}" + (f":{port}" if port is not None else "") + path
    if query is not None:
        kept = [p for p in query.split("&")
                if not (p.split("=", 1)[0].startswith("utm_") or p.split("=", 1)[0] in TRACKING_PARAMS)]
        if kept and kept != [""]:
            out += "?" + "&".join(kept)
    return out
