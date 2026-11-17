import json
from pathlib import Path

import pytest

from toridict import build, parse

HERE = Path(__file__).resolve().parent
FIXTURES = HERE.parents[2] / "spec" / "fixtures"
DATA = HERE / "data"
FREQ = {"run": 300, "run out": 9000, "sprint": 150_000, "color": 900, "moscow": 5000}


def cases(rel: str) -> list:
    return [(c["id"], c) for c in json.loads((FIXTURES / rel).read_text(encoding="utf-8"))["cases"]]


@pytest.fixture
def lexicon() -> build.Lexicon:
    return build.assemble(parse.parse_en(parse.read_jsonl(DATA / "en.jsonl")),
                          parse.parse_ru(parse.read_jsonl(DATA / "ru.jsonl")),
                          FREQ.get)
