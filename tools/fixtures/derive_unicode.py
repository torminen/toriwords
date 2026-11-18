"""Derives data/assigned-13.0.txt from UnicodeData.txt 13.0.0 (pass the downloaded file's path).

    curl -sSfO https://www.unicode.org/Public/13.0.0/ucd/UnicodeData.txt
    uv run python derive_unicode.py UnicodeData.txt
"""

import hashlib
import sys
from pathlib import Path

DST = Path(__file__).parent / "data" / "assigned-13.0.txt"
SOURCE_SHA256 = "bdbffbbfc8ad4d3a6d01b5891510458f3d36f7170422af4ea2bed3211a73e8bb"


def main(src: str) -> None:
    raw = Path(src).read_bytes()
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        sys.exit("not the pinned UnicodeData.txt 13.0.0")
    points, first = [], None
    for line in raw.decode("ascii").splitlines():
        code, name = line.split(";")[:2]
        cp = int(code, 16)
        if name.endswith(", First>"):
            first = cp
        elif name.endswith(", Last>"):
            points.append((first, cp))
        else:
            points.append((cp, cp))
    ranges: list[list[int]] = []
    for a, b in sorted(points):
        if ranges and a == ranges[-1][1] + 1:
            ranges[-1][1] = b
        else:
            ranges.append([a, b])
    lines = ["# Code points assigned in Unicode 13.0 (every code point listed in UnicodeData.txt, ranges expanded).",
             "# Derived from https://www.unicode.org/Public/13.0.0/ucd/UnicodeData.txt",
             f"# sha256 of the source: {SOURCE_SHA256}",
             "# Format: FIRST..LAST (hex), inclusive. Anything not listed is unassigned (Cn) in 13.0."]
    lines += [f"{a:04X}..{b:04X}" for a, b in ranges]
    DST.write_text("\n".join(lines) + "\n", encoding="ascii")


if __name__ == "__main__":
    main(sys.argv[1])
