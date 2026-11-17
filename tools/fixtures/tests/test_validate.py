import json
import shutil

import validate
from conftest import FIXTURES


def test_all_committed_fixtures_are_valid():
    assert validate.validate(FIXTURES) == []


def test_known_deviations_is_empty():
    assert json.loads((FIXTURES / "known-deviations.json").read_text()) == []


def copy(tmp_path):
    root = tmp_path / "fixtures"
    shutil.copytree(FIXTURES, root)
    return root


def test_rejects_code_point_new_in_unicode_14(tmp_path):
    root = copy(tmp_path)
    path = root / "normalization" / "match-key.json"
    doc = json.loads(path.read_text())
    doc["cases"].append({"id": "mk-999", "input": "\U0001FAE0", "expected": "\U0001FAE0"})  # 🫠 melting face, Unicode 14.0
    path.write_text(json.dumps(doc))
    errors = validate.validate(root)
    assert errors == ["normalization/match-key.json: $.cases[38].input: U+1FAE0 is not assigned in Unicode 13.0",
                      "normalization/match-key.json: $.cases[38].expected: U+1FAE0 is not assigned in Unicode 13.0"]


def test_accepts_unicode_13_and_private_use():
    assert validate.is_assigned(0x1FAD6)  # 🫖 teapot, Unicode 13.0
    assert validate.is_assigned(0xE000)
    assert not validate.is_assigned(0xFFFF)  # noncharacter


def test_rejects_schema_violation_and_duplicate_ids(tmp_path):
    root = copy(tmp_path)
    path = root / "ids" / "uuid-v7.json"
    doc = json.loads(path.read_text())
    doc["cases"][1]["id"] = doc["cases"][0]["id"]
    doc["cases"][0]["uuid"] = "NOT-A-UUID"
    path.write_text(json.dumps(doc))
    errors = validate.validate(root)
    assert any("ids/uuid-v7.json: $.cases[0].uuid" in e for e in errors)
    assert "ids/uuid-v7.json: duplicate case id v7-001" in errors


def test_rejects_unknown_kind(tmp_path):
    root = copy(tmp_path)
    (root / "normalization" / "stray.json").write_text('{"kind": "nope", "cases": []}')
    assert validate.validate(root) == ["normalization/stray.json: unknown or missing kind 'nope'"]
