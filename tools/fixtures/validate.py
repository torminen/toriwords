"""Validates spec/fixtures: JSON Schema per fixture kind, unique case ids, and only code points
assigned in Unicode 13.0 (Android's floor). Exit code 1 on any problem.

    uv run python validate.py [fixtures-dir]
"""

import bisect
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

HERE = Path(__file__).resolve().parent
DEFAULT_ROOT = HERE.parents[1] / "spec" / "fixtures"
ASSIGNED = HERE / "data" / "assigned-13.0.txt"


def load_assigned() -> tuple[list[int], list[int]]:
    starts, ends = [], []
    for line in ASSIGNED.read_text(encoding="ascii").splitlines():
        if line and not line.startswith("#"):
            a, b = line.split("..")
            starts.append(int(a, 16))
            ends.append(int(b, 16))
    return starts, ends


_STARTS, _ENDS = load_assigned()


def is_assigned(cp: int) -> bool:
    i = bisect.bisect_right(_STARTS, cp) - 1
    return i >= 0 and cp <= _ENDS[i]


def unassigned(value, path="$"):
    """Yields (json path, code point) for every unassigned code point in keys and string values."""
    if isinstance(value, str):
        for ch in value:
            if not is_assigned(ord(ch)):
                yield path, ord(ch)
    elif isinstance(value, list):
        for i, item in enumerate(value):
            yield from unassigned(item, f"{path}[{i}]")
    elif isinstance(value, dict):
        for key, item in value.items():
            yield from unassigned(key, f"{path}.<key>")
            yield from unassigned(item, f"{path}.{key}")


def validate(root: Path) -> list[str]:
    schemas = {p.name.removesuffix(".schema.json"): json.loads(p.read_text(encoding="utf-8"))
               for p in sorted((root / "schema").glob("*.schema.json"))}
    for schema in schemas.values():
        Draft202012Validator.check_schema(schema)
    errors = []
    files = [p for p in sorted(root.rglob("*.json")) if (root / "schema") not in p.parents]
    for path in files:
        rel = path.relative_to(root)
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as e:
            errors.append(f"{rel}: not valid UTF-8 JSON: {e}")
            continue
        kind = "known-deviations" if rel.as_posix() == "known-deviations.json" else (doc.get("kind") if isinstance(doc, dict) else None)
        if kind not in schemas:
            errors.append(f"{rel}: unknown or missing kind {kind!r}")
            continue
        for err in Draft202012Validator(schemas[kind]).iter_errors(doc):
            errors.append(f"{rel}: {err.json_path}: {err.message[:200]}")
        if isinstance(doc, dict):
            seen = set()
            for case in doc.get("cases", []):
                cid = case.get("id") if isinstance(case, dict) else None
                if cid in seen:
                    errors.append(f"{rel}: duplicate case id {cid}")
                seen.add(cid)
        for where, cp in unassigned(doc):
            errors.append(f"{rel}: {where}: U+{cp:04X} is not assigned in Unicode 13.0")
    return errors


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_ROOT
    errors = validate(root)
    for e in errors:
        print(e, file=sys.stderr)
    print(f"{'FAIL' if errors else 'OK'}: {len(errors)} problem(s) in {root}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
