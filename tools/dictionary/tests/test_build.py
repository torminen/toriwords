from toridict import build


def hw(lex, text, pos):
    return next(h for h in lex.headwords if (h.text, h.pos) == (text, pos))


def test_join_ranks_enwikt_by_sense_then_ruwikt_and_dedupes(lexicon):
    run = hw(lexicon, "run", "verb")
    assert [(t.text, t.origin) for t in run.translations] == [
        ("бежать", "enwikt"), ("бегать", "enwikt"), ("течь", "enwikt"), ("управлять", "ruwikt"), ("руководить", "ruwikt")]
    assert [s.gloss for s in run.senses][-1] == "To manage a business - or a project."  # second etymology merged
    assert [t.text for t in hw(lexicon, "run", "noun").translations] == ["бег", "пробег"]


def test_ru_phrase_joins_en_verb_through_pos_table(lexicon):
    assert [t.text for t in hw(lexicon, "run out", "verb").translations] == ["кончаться", "заканчиваться, иссякать"]
    assert not any(h.text == "run out" and h.pos == "phrase" for h in lexicon.headwords)


def test_unmatched_ru_entries_become_headwords(lexicon):
    follow = hw(lexicon, "follow up", "phrase")
    assert follow.ipa == "[ˌfɒləʊ ˈʌp]" and follow.is_phrase and [t.text for t in follow.translations] == ["преследовать"]
    assert hw(lexicon, "Elbonia", "unknown").translations


def test_proper_names_need_a_russian_translation(lexicon):
    texts = {h.text for h in lexicon.headwords}
    assert "Paris" not in texts and "Moscow" in texts


def test_layout_ids_forms_related(lexicon):
    rows = build.lay_out(lexicon)
    keys = [(r[2], r[3]) for r in rows.headword]
    assert keys == sorted(keys) and [r[0] for r in rows.headword] == list(range(1, len(keys) + 1))
    ids = {(r[1], r[3]): r[0] for r in rows.headword}
    run_v, color = ids[("run", "verb")], ids[("color", "noun")]
    assert ("ran", run_v, "past") in rows.form and ("colour", color, "British") in rows.form
    assert ("runs", run_v, "present singular third-person") in rows.form
    assert not any(f[0] == "run" for f in rows.form)
    # "sprint" (synonym) has no Russian translation, so it is not offered; "runner" is not a headword.
    assert [(r[1], r[2]) for r in rows.related if r[0] == run_v] == [(ids[("run out", "verb")], "phrase")]
    sense_of = {r[0]: (r[1], r[2]) for r in rows.sense}
    run_tr = [r for r in rows.translation_ru if r[1] == run_v]
    assert [(r[3], r[6], sense_of[r[2]][1] if r[2] else None) for r in run_tr] == [
        ("бежать", 1, 2), ("бегать", 2, 2), ("течь", 3, None), ("управлять", 4, None), ("руководить", 5, None)]
    assert next(r[4] for r in rows.translation_ru if r[3] == "Ёлка") == "елка"
    assert rows.example and rows.headword[[r[1] for r in rows.headword].index("run out")][4] == 9000


def test_prune_ladder(lexicon):
    assert build.PRUNE_STEPS == ["none", "examples", "rare-untranslated", "untranslated-50k", "untranslated-20k",
                                 "untranslated-10k", "related"]
    rows = build.lay_out(lexicon, "examples")
    assert not rows.example and rows.related
    texts = {r[1] for r in build.lay_out(lexicon, "rare-untranslated").headword}
    assert "sprint" not in texts and "thee" not in texts and {"run", "color", "follow up"} <= texts
    rows = build.lay_out(lexicon, "untranslated-10k")
    assert rows.related and not rows.example  # related rows outlive headword pruning
    last = build.lay_out(lexicon, "related")
    assert not last.related and not last.example and last.headword == rows.headword  # cumulative: keeps the 10k cut


def _tr(text):
    return build.Translation(text, None, "enwikt")


def test_related_capped_to_app_order_and_needs_translated_targets():
    words = {f"w{i}": i * 10 for i in range(1, 12)}  # w1 most frequent
    src = build.Headword("base", "base", "noun", None, translations=[_tr("база")], freq_rank=5)
    src.related = [(w, "derived") for w in words] + [("rare", "synonym"), ("bare", "synonym"), ("w11", "synonym")]
    targets = [build.Headword(w, w, "noun", None, translations=[_tr("x")], freq_rank=r) for w, r in words.items()]
    targets += [build.Headword("rare", "rare", "noun", None, translations=[_tr("редкий")]),  # freq_rank NULL
                build.Headword("bare", "bare", "noun", None, freq_rank=1)]  # no RU translation: never offered
    rows = build.lay_out(build.Lexicon([src, *targets], []))
    ids = {r[1]: r[0] for r in rows.headword}
    got = {r[1]: r[2] for r in rows.related if r[0] == ids["base"]}
    # synonyms first (w11 by freq, then rare with NULL rank), then derived by freq_rank; 8 in total
    assert got == {ids["w11"]: "synonym", ids["rare"]: "synonym", **{ids[f"w{i}"]: "derived" for i in range(1, 7)}}
    assert [r[1] for r in rows.related if r[0] == ids["base"]] == sorted(got)  # insert order: (headword_id, target id)
    assert build.RELATED_LIMIT == 8


def test_keep_keys_selects_a_subset(lexicon):
    rows = build.lay_out(lexicon, keep_keys={"run", "sprint"})
    assert {r[1] for r in rows.headword} == {"run", "sprint"}
    assert all(r[1] <= len(rows.headword) for r in rows.related + rows.form)
