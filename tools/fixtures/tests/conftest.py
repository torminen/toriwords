import json
from pathlib import Path

FIXTURES = Path(__file__).resolve().parents[3] / "spec" / "fixtures"


def load(rel: str) -> dict:
    return json.loads((FIXTURES / rel).read_text(encoding="utf-8"))


def cases(rel: str) -> list:
    return [(c["id"], c) for c in load(rel)["cases"]]
