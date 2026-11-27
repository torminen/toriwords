"""Join, rank, prune and lay out rows for dictionary.sqlite."""

from collections.abc import Callable, Iterable
from dataclasses import dataclass, field

from .parse import Entry, FormOf, Sense, Translation, ru_pos_candidates
from .text import match_key, search_fold

PHRASE_POS = {"phrase", "prep_phrase", "adv_phrase", "proverb"}
RELATED_ORDER = {"synonym": 0, "related": 1, "derived": 2, "phrase": 3}
ORIGIN_ORDER = {"enwikt": 0, "ruwikt": 1}
# Prune ladder (cumulative): examples → headwords without RU translation and freq_rank > 100,000 → the same with
# 50k/20k/10k → related rows as the last resort. Related rows are small once capped, and the app's Related words row
# needs them, so they outlive rare headwords.
PRUNE_STEPS = ["none", "examples", "rare-untranslated", "untranslated-50k", "untranslated-20k", "untranslated-10k",
               "related"]
RELATED_LIMIT = 8  # the app shows the first 8 related headwords; rows past that are never read
UNTRANSLATED_MAX_RANK = {"rare-untranslated": 100_000, "untranslated-50k": 50_000, "untranslated-20k": 20_000,
                         "untranslated-10k": 10_000}


@dataclass
class Headword:
    text: str
    key: str
    pos: str
    ipa: str | None
    senses: list[Sense] = field(default_factory=list)
    translations: list[Translation] = field(default_factory=list)
    forms: list[tuple[str, str]] = field(default_factory=list)
    related: list[tuple[str, str]] = field(default_factory=list)
    freq_rank: int | None = None

    @property
    def is_phrase(self) -> bool:
        return " " in self.key or self.pos in PHRASE_POS


@dataclass
class Lexicon:
    headwords: list[Headword]
    form_of: list[FormOf]


def assemble(en: Iterable[Entry | FormOf], ru: Iterable[Entry], freq_rank: Callable[[str], int | None]) -> Lexicon:
    merged: dict[tuple[str, str], Headword] = {}
    form_of: list[FormOf] = []
    for item in en:
        if isinstance(item, FormOf):
            form_of.append(item)
            continue
        key = match_key(item.text)
        if not key:
            continue
        h = merged.setdefault((item.text, item.pos), Headword(item.text, key, item.pos, item.ipa))
        h.ipa = h.ipa or item.ipa
        h.senses += item.senses
        h.translations += item.translations
        h.forms += item.forms
        h.related += item.related

    by_key: dict[str, list[Headword]] = {}
    for h in merged.values():
        by_key.setdefault(h.key, []).append(h)

    for r in ru:
        key = match_key(r.text)
        if not key:
            continue
        h = _join_target(by_key.get(key, []), r)
        if h is None:
            allowed = ru_pos_candidates(r.pos)
            pos = allowed[0] if allowed else r.pos
            h = merged.setdefault((r.text, pos), Headword(r.text, key, pos, r.ipa))
            if h not in by_key.setdefault(key, []):
                by_key[key].append(h)
        h.ipa = h.ipa or r.ipa
        h.translations += r.translations

    headwords = []
    for h in merged.values():
        if h.pos == "name" and not h.translations:
            continue  # proper names without a Russian translation
        h.translations = _rank(h)
        h.freq_rank = freq_rank(h.key)
        headwords.append(h)
    return Lexicon(headwords, form_of)


def _join_target(candidates: list[Headword], r: Entry) -> Headword | None:
    """Join a ruwikt entry to an enwikt headword by (key, pos) through the POS table; exact text wins."""
    allowed = ru_pos_candidates(r.pos)
    pools = [candidates] if allowed is None else [[h for h in candidates if h.pos == p] for p in allowed]
    for pool in pools:
        if pool:
            return next((h for h in pool if h.text == r.text), pool[0])
    return None


def _rank(h: Headword) -> list[Translation]:
    """Sense order, then enwikt (table order) before ruwikt (first sense first); dedupe by translation key."""
    ordinal = {id(s): i for i, s in enumerate(h.senses)}
    order = sorted(range(len(h.translations)), key=lambda i: (
        ordinal.get(id(h.translations[i].sense), len(h.senses)), ORIGIN_ORDER[h.translations[i].origin], i))
    seen, out = set(), []
    for i in order:
        t = h.translations[i]
        k = match_key(t.text)
        if k and k not in seen:
            seen.add(k)
            out.append(t)
    return out


@dataclass
class Rows:
    headword: list[tuple] = field(default_factory=list)
    sense: list[tuple] = field(default_factory=list)
    translation_ru: list[tuple] = field(default_factory=list)
    form: list[tuple] = field(default_factory=list)
    example: list[tuple] = field(default_factory=list)
    related: list[tuple] = field(default_factory=list)


def _null_last(rank: int | None) -> tuple:
    return (rank is None, rank or 0)


def lay_out(lex: Lexicon, prune: str = "none", keep_keys: set[str] | None = None) -> Rows:
    """Select, give IDs in (key, pos, text) order and produce rows in insert order (key, then id)."""
    level = PRUNE_STEPS.index(prune)
    hws = [h for h in lex.headwords if keep_keys is None or h.key in keep_keys]
    limit = min((UNTRANSLATED_MAX_RANK[p] for p in PRUNE_STEPS[:level + 1] if p in UNTRANSLATED_MAX_RANK), default=None)
    if limit is not None:
        hws = [h for h in hws if h.translations or (h.freq_rank is not None and h.freq_rank <= limit)]
    hws.sort(key=lambda h: (h.key, h.pos, h.text))
    hid = {id(h): i for i, h in enumerate(hws, 1)}
    by_key: dict[str, list[Headword]] = {}
    for h in hws:
        by_key.setdefault(h.key, []).append(h)

    rows = Rows()
    sense_id = translation_id = 0
    forms: dict[tuple[str, int], str] = {}  # first-seen tags win: unions of conjugation tags are noise
    for h in hws:
        i = hid[id(h)]
        rows.headword.append((i, h.text, h.key, h.pos, h.freq_rank, h.ipa, int(h.is_phrase)))
        sid = {}
        for ordinal, s in enumerate(h.senses, 1):
            sense_id += 1
            sid[id(s)] = sense_id
            rows.sense.append((sense_id, i, ordinal, s.gloss, s.tags or None))
            if level < 1:
                rows.example += [(sense_id, ex) for ex in s.examples]
        for rank, t in enumerate(h.translations, 1):
            translation_id += 1
            rows.translation_ru.append((translation_id, i, sid.get(id(t.sense)), t.text, search_fold(t.text), t.origin, rank))
        for text, tags in h.forms:
            fk = match_key(text)
            if fk and fk != h.key:
                forms.setdefault((fk, i), tags)

    for f in lex.form_of:
        base, fk = match_key(f.base), match_key(f.form)
        if fk and fk != base:
            for h in by_key.get(base, ()):
                if h.pos == f.pos:
                    forms.setdefault((fk, hid[id(h)]), f.tags)
    rows.form = [(fk, i, tags or None) for (fk, i), tags in sorted(forms.items())]

    if prune != "related":
        kinds = {v: k for k, v in RELATED_ORDER.items()}
        for h in hws:
            best: dict[int, tuple[int, Headword]] = {}
            for word, kind in h.related:
                # Targets need a Russian translation: the app's Add saves the suggestion with it.
                targets = [t for t in by_key.get(match_key(word), ()) if t.key != h.key and t.translations]
                if not targets:
                    continue
                t = min(targets, key=lambda t: (_null_last(t.freq_rank), hid[id(t)]))
                j = hid[id(t)]
                best[j] = (min(best.get(j, (9,))[0], RELATED_ORDER[kind]), t)
            # Keep the first RELATED_LIMIT in the app's order: kind, freq_rank NULL last, target id.
            top = sorted(best.items(), key=lambda jk: (jk[1][0], _null_last(jk[1][1].freq_rank), jk[0]))[:RELATED_LIMIT]
            rows.related += [(hid[id(h)], j, kinds[k]) for j, (k, _) in sorted(top)]
    return rows


def frequency_ranker(wordlist: str = "large") -> Callable[[str], int | None]:
    """freq_rank = 1 + number of wordfreq entries strictly more frequent than the key; NULL when the key is not
    a wordfreq entry. Multi-token keys get NULL: wordfreq's combined estimate is about the rarest token's
    frequency ("perfect all-kill" would rank ~1,500), not the phrase's."""
    import bisect

    from wordfreq import get_frequency_dict

    freqs = get_frequency_dict("en", wordlist)
    neg = sorted(-f for f in freqs.values())

    def rank(key: str) -> int | None:
        f = freqs.get(key)
        return bisect.bisect_left(neg, -f) + 1 if f else None

    return rank
