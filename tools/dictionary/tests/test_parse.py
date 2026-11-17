from conftest import DATA
from toridict.parse import Entry, FormOf, parse_en, parse_ru, read_jsonl, ru_variants


def en_items():
    return list(parse_en(read_jsonl(DATA / "en.jsonl")))


def test_en_keeps_only_english_lemmas_and_reports_forms():
    items = en_items()
    entries = [(e.text, e.pos) for e in items if isinstance(e, Entry)]
    assert ("xyzzy", "intj") not in entries and ("Lauf", "noun") not in entries
    assert ("ran", "verb") not in entries
    forms = [(f.form, f.base, f.pos, f.tags) for f in items if isinstance(f, FormOf)]
    assert forms == [("ran", "run", "verb", "past"), ("colour", "color", "noun", "British")]


def test_en_senses_filters_examples_translations_forms():
    run = next(e for e in en_items() if isinstance(e, Entry) and (e.text, e.pos) == ("run", "verb"))
    assert [s.gloss for s in run.senses] == ["To move swiftly.", "To go at a fast pace; to move 'quickly'."]
    assert run.senses[0].examples == ["Run, and you might still catch the train!"]
    assert run.ipa == "/ɹʌn/"
    assert [(t.text, run.senses.index(t.sense) if t.sense else None) for t in run.translations] == [
        ("бежать", 1), ("бегать", 1), ("Бегать", 1), ("течь", None)]
    assert run.forms == [("runs", "present singular third-person"), ("ran", "past"),
                         ("running", "participle present"), ("run", "infinitive")]
    assert run.related == [("sprint", "synonym"), ("run out", "phrase"), ("runner", "derived")]


def test_rare_only_senses_are_kept():
    thee = next(e for e in en_items() if isinstance(e, Entry) and e.text == "thee")
    assert [s.tags for s in thee.senses] == ["archaic"]


def test_ru_variants_split_strip_labels_and_drop_cross_references():
    assert ru_variants("экон. амер. управлять; руководить.") == ["управлять", "руководить"]
    assert ru_variants("то же, что misuse") == []
    assert ru_variants("пробе́г") == ["пробег"]


def test_ru_parser_skips_entries_without_russian_text():
    words = [(e.text, e.pos) for e in parse_ru(read_jsonl(DATA / "ru.jsonl"))]
    assert words == [("run", "verb"), ("run", "noun"), ("run out", "phrase"), ("follow up", "phrase"), ("Elbonia", "unknown")]


def test_ru_variants_drop_encyclopedic_definitions():
    assert ru_variants("а" * 101 + "; бег") == ["бег"]


def test_obsolete_form_of_senses_give_no_form():
    rec = {"word": "runneth", "pos": "verb", "lang_code": "en",
           "senses": [{"glosses": ["x"], "tags": ["archaic", "form-of"], "form_of": [{"word": "run"}]}]}
    assert list(parse_en([rec])) == []


def test_ru_variants_split_only_outside_parentheses():
    assert ru_variants("приют (у улитки; для защиты); дом") == ["приют (у улитки; для защиты)", "дом"]
