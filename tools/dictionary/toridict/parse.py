"""Streaming parsers for the two kaikki.org / wiktextract JSONL shapes.

enwiktionary: English entries; Russian translations live in `translations` (top level, mapped to a sense
via `_dis1`, or inside a sense). ruwiktionary: English entries whose sense glosses are Russian definitions.
"""

import gzip
import json
import re
from collections.abc import Iterable, Iterator
from dataclasses import dataclass, field
from pathlib import Path

from .text import clean, clean_ru

DROP_IF_OTHERS = {"obsolete", "archaic", "rare"}
SKIP_FORM_TAGS = {"table-tags", "inflection-template", "class", "canonical", "romanization",
                  "archaic", "obsolete", "dated", "nonstandard", "misspelling"}
SKIP_SENSE_TAGS = {"form-of", "alt-of", "no-gloss"}
MAX_EXAMPLES = 3
MAX_EXAMPLE_LEN = 200
MAX_RU_VARIANT_LEN = 100  # longer ruwikt "variants" are encyclopedic definitions, not translations

# ruwiktionary POS spellings → enwiktionary POS candidates, best first (join on (key, pos)).
# `None` = any POS (the entry is matched to the first enwikt headword with the key).
RU_POS = {
    "interj": ["intj"], "onomatopeia": ["intj"],
    "abbrev": ["abbrev", "noun", "name", "adj", "phrase"],
    "phrase": ["phrase", "verb", "noun", "prep_phrase", "adv", "adj", "intj", "proverb", "adv_phrase"],
    "unknown": None,
}


def ru_pos_candidates(pos: str) -> list[str] | None:
    return RU_POS.get(pos, [pos])


@dataclass
class Sense:
    gloss: str
    tags: str
    examples: list[str] = field(default_factory=list)


@dataclass
class Translation:
    text: str
    sense: Sense | None
    origin: str  # "enwikt" | "ruwikt"


@dataclass
class Entry:
    """One source entry: a headword candidate (merged later by (text, pos))."""
    text: str
    pos: str
    ipa: str | None
    senses: list[Sense] = field(default_factory=list)
    translations: list[Translation] = field(default_factory=list)
    forms: list[tuple[str, str]] = field(default_factory=list)      # (form text, tags)
    related: list[tuple[str, str]] = field(default_factory=list)    # (word, kind)


@dataclass
class FormOf:
    """A non-lemma entry: `form` is an inflection/alternative of `base` (same pos)."""
    form: str
    base: str
    pos: str
    tags: str


def read_jsonl(path: Path) -> Iterator[dict]:
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                yield json.loads(line)


def _first_ipa(sounds: list[dict] | None) -> str | None:
    for s in sounds or ():
        if s.get("ipa"):
            return clean(s["ipa"])
    return None


def _tags(tags: Iterable[str]) -> str:
    return " ".join(t for t in tags if t not in SKIP_SENSE_TAGS)


def _related(rec: dict, out: list[tuple[str, str]]) -> None:
    for src, kind in (("synonyms", "synonym"), ("related", "related"), ("derived", "derived")):
        for r in rec.get(src) or ():
            w = clean(r.get("word") or "")
            if w and not w.startswith(("Thesaurus:", "Appendix:")):
                out.append((w, "phrase" if kind == "derived" and " " in w else kind))


def _ru_translation(t: dict) -> str | None:
    if t.get("lang_code", t.get("code")) != "ru" or not t.get("word"):
        return None
    return clean_ru(t["word"]) or None


def parse_en(records: Iterable[dict]) -> Iterator[Entry | FormOf]:
    for rec in records:
        if rec.get("lang_code") != "en" or not rec.get("word"):
            continue
        word, pos = clean(rec["word"]), rec.get("pos") or "unknown"
        raw_senses = rec.get("senses") or []
        lemma: list[tuple[int, dict]] = []
        for i, s in enumerate(raw_senses):
            links = (s.get("form_of") or []) + (s.get("alt_of") or [])
            if links:
                if SKIP_FORM_TAGS & set(s.get("tags") or ()):
                    continue
                tags = " ".join(t for t in s.get("tags") or () if t not in SKIP_SENSE_TAGS)
                for link in links:
                    if link.get("word"):
                        yield FormOf(word, clean(link["word"]), pos, tags or "alternative")
                continue
            if not s.get("glosses") or "no-gloss" in (s.get("tags") or ()):
                continue
            lemma.append((i, s))
        if any(not DROP_IF_OTHERS & set(s.get("tags") or ()) for _, s in lemma):
            lemma = [(i, s) for i, s in lemma if not DROP_IF_OTHERS & set(s.get("tags") or ())]
        if not lemma:
            continue

        entry = Entry(word, pos, _first_ipa(rec.get("sounds")))
        by_index: dict[int, Sense] = {}
        for i, s in lemma:
            gloss = clean(s["glosses"][-1])
            if not gloss:
                continue
            sense = Sense(gloss, _tags(s.get("tags") or ()))
            for ex in s.get("examples") or ():
                text = clean(ex.get("text") or "")
                if ex.get("type") == "example" and text and len(text) <= MAX_EXAMPLE_LEN \
                        and len(sense.examples) < MAX_EXAMPLES:
                    sense.examples.append(text)
            entry.senses.append(sense)
            by_index[i] = sense
            for t in s.get("translations") or ():
                if (ru := _ru_translation(t)):
                    entry.translations.append(Translation(ru, sense, "enwikt"))
            _related(s, entry.related)
        if not entry.senses:
            continue
        for t in rec.get("translations") or ():
            if (ru := _ru_translation(t)):
                entry.translations.append(Translation(ru, by_index.get(_dis_sense(t)), "enwikt"))
        _related(rec, entry.related)
        for f in rec.get("forms") or ():
            tags = f.get("tags") or ()
            text = clean(f.get("form") or "")
            if text and tags and not SKIP_FORM_TAGS & set(tags):
                entry.forms.append((text, " ".join(sorted(tags))))
        yield entry


def _dis_sense(t: dict) -> int | None:
    """Index of the source sense a top-level translation belongs to: the first maximum of `_dis1`, if > 0."""
    try:
        scores = [int(x) for x in (t.get("_dis1") or "").split()]
    except ValueError:
        return None
    if not scores or max(scores) <= 0:
        return None
    return scores.index(max(scores))


# --- ruwiktionary ---------------------------------------------------------------------------------

# Leading domain/register labels rendered into ruwikt glosses: "экон. ", "амер. спорт. ".
_RU_LABELS = re.compile(r"^(?:[а-яё]{2,10}\.\s+)+")
_LATIN = re.compile(r"[A-Za-z]")


def ru_variants(gloss: str) -> list[str]:
    """Split a ruwikt definition into translation variants on ';', dropping labels and cross-references."""
    out = []
    for part in _split_top_level(clean_ru(gloss)):
        part = _RU_LABELS.sub("", part.strip()).strip(" ,.:")
        if part and len(part) <= MAX_RU_VARIANT_LEN and not _LATIN.search(part):
            out.append(part)
    return out


def _split_top_level(s: str) -> list[str]:
    parts, depth, start = [], 0, 0
    for i, c in enumerate(s):
        depth += (c in "([") - (c in ")]")
        if c == ";" and depth <= 0:
            parts.append(s[start:i])
            start = i + 1
    return parts + [s[start:]]


def parse_ru(records: Iterable[dict]) -> Iterator[Entry]:
    for rec in records:
        if rec.get("lang_code") != "en" or not rec.get("word"):
            continue
        entry = Entry(clean(rec["word"]), rec.get("pos") or "unknown", _first_ipa(rec.get("sounds")))
        for s in rec.get("senses") or ():
            if not s.get("glosses") or "no-gloss" in (s.get("tags") or ()):
                continue
            for v in ru_variants(s["glosses"][-1]):
                entry.translations.append(Translation(v, None, "ruwikt"))
        if entry.translations:
            yield entry
