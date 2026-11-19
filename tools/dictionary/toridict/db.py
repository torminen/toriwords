"""Deterministic writer for dictionary.sqlite. Schema is normative (shared with the apps)."""

import os
import sqlite3
from pathlib import Path

from .build import Rows

SCHEMA = """
CREATE TABLE meta (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
CREATE TABLE headword (
  id INTEGER PRIMARY KEY, text TEXT NOT NULL, key TEXT NOT NULL, pos TEXT NOT NULL,
  freq_rank INTEGER, ipa TEXT, is_phrase INTEGER NOT NULL);
CREATE TABLE sense (
  id INTEGER PRIMARY KEY, headword_id INTEGER NOT NULL REFERENCES headword(id),
  ordinal INTEGER NOT NULL, gloss_en TEXT NOT NULL, tags TEXT);
CREATE TABLE translation_ru (
  id INTEGER PRIMARY KEY, headword_id INTEGER NOT NULL REFERENCES headword(id),
  sense_id INTEGER REFERENCES sense(id), text TEXT NOT NULL, text_folded TEXT NOT NULL,
  origin TEXT NOT NULL CHECK (origin IN ('enwikt', 'ruwikt')), rank INTEGER NOT NULL);
CREATE TABLE form (form_key TEXT NOT NULL, headword_id INTEGER NOT NULL REFERENCES headword(id), form_tags TEXT);
CREATE TABLE example (sense_id INTEGER NOT NULL REFERENCES sense(id), text_en TEXT NOT NULL);
CREATE TABLE related (
  headword_id INTEGER NOT NULL REFERENCES headword(id), related_headword_id INTEGER NOT NULL REFERENCES headword(id),
  kind TEXT NOT NULL CHECK (kind IN ('synonym', 'related', 'derived', 'phrase')));
"""

INDEXES = """
CREATE INDEX headword_key ON headword(key);
CREATE INDEX sense_headword ON sense(headword_id, ordinal);
CREATE INDEX translation_ru_headword ON translation_ru(headword_id, rank);
CREATE INDEX form_key ON form(form_key);
CREATE INDEX example_sense ON example(sense_id);
CREATE INDEX related_headword ON related(headword_id);
CREATE VIRTUAL TABLE ru_fts USING fts5(
  text_folded, content='translation_ru', content_rowid='id', tokenize='unicode61 remove_diacritics 0', columnsize=0);
INSERT INTO ru_fts(ru_fts) VALUES ('rebuild');
"""


def write(rows: Rows, meta: dict[str, str], path: Path) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.unlink(missing_ok=True)
    con = sqlite3.connect(tmp, isolation_level=None)
    try:
        con.execute("PRAGMA page_size = 4096")
        con.execute("PRAGMA encoding = 'UTF-8'")
        con.execute("PRAGMA journal_mode = OFF")
        con.executescript(SCHEMA)  # executescript commits first, so it stays outside the insert transaction
        con.execute("BEGIN")
        con.executemany("INSERT INTO meta VALUES (?, ?)", sorted(meta.items()))
        con.executemany("INSERT INTO headword VALUES (?, ?, ?, ?, ?, ?, ?)", rows.headword)
        con.executemany("INSERT INTO sense VALUES (?, ?, ?, ?, ?)", rows.sense)
        con.executemany("INSERT INTO translation_ru VALUES (?, ?, ?, ?, ?, ?, ?)", rows.translation_ru)
        con.executemany("INSERT INTO form VALUES (?, ?, ?)", rows.form)
        con.executemany("INSERT INTO example VALUES (?, ?)", rows.example)
        con.executemany("INSERT INTO related VALUES (?, ?, ?)", rows.related)
        con.execute("COMMIT")
        con.executescript(INDEXES)
        assert con.execute("PRAGMA encoding").fetchone()[0] == "UTF-8", "dictionary.sqlite must be UTF-8"
        con.execute("VACUUM")
        assert con.execute("PRAGMA page_size").fetchone()[0] == 4096
        assert con.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
    finally:
        con.close()
    os.replace(tmp, path)
