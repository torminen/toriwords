import os
import sqlite3
import statistics
import time
from pathlib import Path

import pytest

from conftest import cases
from toridict import build, db

META = {"dictionary_version": "2026.11.1-test", "licence": "CC BY-SA 4.0"}
AUTOCOMPLETE = ("SELECT id FROM headword WHERE key >= :p AND key < :p || x'FFFF' "
                "ORDER BY freq_rank IS NULL, freq_rank, key, id LIMIT 8")
SCHEMA = {
    "meta": ["key", "value"],
    "headword": ["id", "text", "key", "pos", "freq_rank", "ipa", "is_phrase"],
    "sense": ["id", "headword_id", "ordinal", "gloss_en", "tags"],
    "translation_ru": ["id", "headword_id", "sense_id", "text", "text_folded", "origin", "rank"],
    "form": ["form_key", "headword_id", "form_tags"],
    "example": ["sense_id", "text_en"],
    "related": ["headword_id", "related_headword_id", "kind"],
    "ru_fts": ["text_folded"],
}


def written(lexicon, path: Path) -> sqlite3.Connection:
    db.write(build.lay_out(lexicon), META, path)
    return sqlite3.connect(f"file:{path}?mode=ro&immutable=1", uri=True)


def test_schema_matches_doc_36_8_2(lexicon, tmp_path):
    con = written(lexicon, tmp_path / "d.sqlite")
    for table, cols in SCHEMA.items():
        assert [r[1] for r in con.execute(f"PRAGMA table_info({table})")] == cols
    assert con.execute("PRAGMA encoding").fetchone()[0] == "UTF-8"
    assert con.execute("PRAGMA page_size").fetchone()[0] == 4096
    assert "headword_key" in [r[1] for r in con.execute("PRAGMA index_list(headword)")]
    assert dict(con.execute("SELECT key, value FROM meta")) == META


def test_queries_from_8_2(lexicon, tmp_path):
    con = written(lexicon, tmp_path / "d.sqlite")
    hits = con.execute(f"SELECT text, pos FROM headword WHERE id IN ({AUTOCOMPLETE}) ", {"p": "ru"}).fetchall()
    assert sorted(hits) == [("run", "noun"), ("run", "verb"), ("run out", "verb")]
    base = con.execute("SELECT h.text FROM form f JOIN headword h ON h.id = f.headword_id WHERE f.form_key = 'ran'").fetchall()
    assert base == [("run",)]
    reverse = con.execute("""SELECT DISTINCT h.text FROM ru_fts JOIN translation_ru t ON t.id = ru_fts.rowid
                             JOIN headword h ON h.id = t.headword_id WHERE ru_fts MATCH '"бег"*' ORDER BY h.text""").fetchall()
    assert reverse == [("run",)]
    assert con.execute("""SELECT count(*) FROM ru_fts WHERE ru_fts MATCH '"елка"'""").fetchone()[0] == 1


def test_same_inputs_give_same_bytes(lexicon, tmp_path):
    written(lexicon, tmp_path / "a.sqlite").close()
    written(lexicon, tmp_path / "b.sqlite").close()
    assert (tmp_path / "a.sqlite").read_bytes() == (tmp_path / "b.sqlite").read_bytes()


@pytest.mark.parametrize("cid,case", [c for c in cases("normalization/text-order.json") if "prefix" in c[1]])
def test_text_order_fixture_through_autocomplete_range(cid, case, tmp_path):
    rows = build.Rows(headword=[(i, k, k, "noun", None, None, 0) for i, k in enumerate(case["keys"], 1)])
    db.write(rows, META, tmp_path / "o.sqlite")
    con = sqlite3.connect(tmp_path / "o.sqlite")
    got = [r[0] for r in con.execute(
        "SELECT key FROM headword WHERE key >= :p AND key < :p || x'FFFF' ORDER BY key, id", {"p": case["prefix"]})]
    assert got == case["expected"]


FULL = Path(os.environ.get("TORI_DICTIONARY", Path(__file__).resolve().parents[1] / "dictionary.sqlite"))


@pytest.mark.skipif(not FULL.exists(), reason="full dictionary.sqlite not built")
def test_autocomplete_on_full_dictionary_under_10_ms():
    con = sqlite3.connect(f"file:{FULL}?mode=ro&immutable=1", uri=True)
    prefixes = ["a", "co", "re", "st", "pr", "th", "in", "ma", "un", "de", "take o", "run", "zz", "qu"]
    con.execute(AUTOCOMPLETE, {"p": "warmup"}).fetchall()
    timings = []
    for p in prefixes:
        t = time.perf_counter()
        assert con.execute(AUTOCOMPLETE, {"p": p}).fetchall() or p == "zz"
        timings.append((time.perf_counter() - t) * 1000)
    assert max(timings) < 10, dict(zip(prefixes, timings))
    assert statistics.median(timings) < 5
