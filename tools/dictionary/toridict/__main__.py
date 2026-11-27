"""CLI: `uv run python -m toridict {pin,fetch,build}` — see README.md."""

import argparse
import hashlib
import json
import platform
import re
import sqlite3
import sys
import time
import urllib.request
from importlib.metadata import version as pkg_version
from pathlib import Path

from . import build, db, parse, report

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
CACHE = ROOT / "cache"
SOURCES = ROOT / "sources.json"
SIZE_BUDGET = 61 * 1024 * 1024
RELEASE_URL = "https://github.com/torminen/toriwords/releases/download/dictionary-{v}/dictionary.sqlite"
LICENCE_TEXT = ("Dictionary data from Wiktionary (en.wiktionary.org, ru.wiktionary.org), Wiktionary contributors, "
                "CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/), extracted with wiktextract "
                "(kaikki.org); frequency ranks from wordfreq (CC BY-SA 4.0). Modified: filtered, merged, normalised.")
KAIKKI = {
    "enwikt": ("https://kaikki.org/dictionary/English/words/kaikki.org-dictionary-English-words.jsonl.gz",
               "https://kaikki.org/dictionary/English/index.html"),
    "ruwikt": ("https://kaikki.org/ruwiktionary/%D0%90%D0%BD%D0%B3%D0%BB%D0%B8%D0%B9%D1%81%D0%BA%D0%B8%D0%B9/"
               "kaikki.org-dictionary-%D0%90%D0%BD%D0%B3%D0%BB%D0%B8%D0%B9%D1%81%D0%BA%D0%B8%D0%B9.jsonl.gz",
               "https://kaikki.org/ruwiktionary/%D0%90%D0%BD%D0%B3%D0%BB%D0%B8%D0%B9%D1%81%D0%BA%D0%B8%D0%B9/index.html"),
}
_PROVENANCE = re.compile(r"extracted on (\S+) from the (\w+) dump dated (\S+) using\s+wiktextract\s+\(([^)]*)\)")


def log(msg: str) -> None:
    print(f"[toridict] {msg}", file=sys.stderr, flush=True)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_suffix(dest.suffix + ".part")
    log(f"downloading {url}")
    with urllib.request.urlopen(url) as r, open(part, "wb") as f:
        while chunk := r.read(1 << 20):
            f.write(chunk)
    part.replace(dest)


def cmd_pin(args) -> None:
    """Download the current kaikki dumps and pin URL, size, SHA-256 and provenance in sources.json."""
    pinned = {"dictionary_version": args.version, "inputs": {}}
    for name, (url, page) in KAIKKI.items():
        dest = CACHE / f"{name}-en.jsonl.gz"
        download(url, dest)
        html = urllib.request.urlopen(page).read().decode("utf-8")
        m = _PROVENANCE.search(re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html)))
        if not m:
            sys.exit(f"cannot read dump provenance from {page}")
        pinned["inputs"][name] = {
            "url": url, "file": dest.name, "size": dest.stat().st_size, "sha256": sha256_file(dest),
            "wiki": m.group(2), "dump_date": m.group(3), "extracted": m.group(1),
            "wiktextract": " ".join(m.group(4).replace(" and ", " ").split()),
        }
    SOURCES.write_text(json.dumps(pinned, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    log(f"pinned {SOURCES}")


def fetch_inputs(sources: dict) -> dict[str, Path]:
    paths = {}
    for name, src in sources["inputs"].items():
        path = CACHE / src["file"]
        if not path.exists() or sha256_file(path) != src["sha256"]:
            download(src["url"], path)
            if (got := sha256_file(path)) != src["sha256"]:
                path.unlink()
                sys.exit(f"{name}: SHA-256 mismatch ({got} != {src['sha256']}); re-pin with `python -m toridict pin`")
        paths[name] = path
    return paths


def build_hash(sources: dict, prune: str, sample: bool) -> str:
    h = hashlib.sha256()
    for name, src in sorted(sources["inputs"].items()):
        h.update(f"{name}:{src['sha256']}\n".encode())
    for f in sorted((ROOT / "toridict").glob("*.py")):
        h.update(f"{f.name}:{sha256_file(f)}\n".encode())
    h.update(f"wordfreq:{pkg_version('wordfreq')}\nprune:{prune}\nsample:{sample}\n".encode())
    return h.hexdigest()


def make_meta(sources: dict, version: str, prune: str, sample: bool) -> dict[str, str]:
    meta = {
        "dictionary_version": version + ("-sample" if sample else ""),
        "licence": "CC BY-SA 4.0",
        "licence_text": LICENCE_TEXT,
        "build_hash": build_hash(sources, prune, sample),
        "prune": prune,
        "wordfreq_version": pkg_version("wordfreq"),
        "sqlite_version": sqlite3.sqlite_version,
        "python_version": platform.python_version(),
    }
    wiktextract = set()
    for name, src in sources["inputs"].items():
        for k in ("url", "sha256", "size", "dump_date", "extracted"):
            meta[f"{name}_{k}"] = str(src[k])
        wiktextract.add(src["wiktextract"])
    meta["wiktextract_version"] = " / ".join(sorted(wiktextract))
    return meta


def cmd_build(args) -> None:
    started = time.monotonic()
    sources = json.loads(SOURCES.read_text(encoding="utf-8"))
    version = sources["dictionary_version"]
    paths = fetch_inputs(sources)
    log("parsing + joining")
    lex = build.assemble(parse.parse_en(parse.read_jsonl(paths["enwikt"])),
                         parse.parse_ru(parse.read_jsonl(paths["ruwikt"])),
                         build.frequency_ranker())
    log(f"{len(lex.headwords)} headwords assembled in {time.monotonic() - started:.0f}s")

    out = Path(args.out)
    for prune in build.PRUNE_STEPS:
        db.write(build.lay_out(lex, prune), make_meta(sources, version, prune, False), out)
        size = out.stat().st_size
        log(f"prune={prune}: {size / 1048576:.1f} MiB")
        if size <= SIZE_BUDGET:
            break
    else:
        sys.exit(f"{out} is {size} bytes after every prune step; budget {SIZE_BUDGET}")

    digest = sha256_file(out)
    (ROOT / "dictionary.sqlite.sha256").write_text(f"{digest}  dictionary.sqlite\n", encoding="utf-8")
    (ROOT / "release.json").write_text(json.dumps({
        "dictionary_version": version, "tag": f"dictionary-{version}", "asset_url": RELEASE_URL.format(v=version),
        "sha256": digest, "size": size}, indent=2) + "\n", encoding="utf-8")

    coverage_list = report.coverage_list(ROOT / "coverage")
    sample = Path(args.sample)
    sample_keys = report.sample_keys(coverage_list[1])
    # The sample keeps examples and related rows (prune "none") so app tests see every table filled.
    db.write(build.lay_out(lex, "none", keep_keys=sample_keys), make_meta(sources, version, "none", True), sample)

    (ROOT / "build-report.md").write_text(report.render(
        out, digest, sources, coverage_list, sample, time.monotonic() - started), encoding="utf-8")
    log(f"done: {out} {digest}")


def main() -> None:
    ap = argparse.ArgumentParser(prog="toridict")
    sub = ap.add_subparsers(required=True)
    p = sub.add_parser("pin", help="download current kaikki dumps and pin them in sources.json")
    p.add_argument("--version", required=True, help="dictionary_version of the next release, e.g. 2026.12.1")
    p.set_defaults(fn=cmd_pin)
    p = sub.add_parser("fetch", help="download pinned inputs into cache/ and verify SHA-256")
    p.set_defaults(fn=lambda a: fetch_inputs(json.loads(SOURCES.read_text(encoding="utf-8"))))
    p = sub.add_parser("build", help="build dictionary.sqlite, the sample, .sha256, release.json, build-report.md")
    p.add_argument("--out", default=str(ROOT / "dictionary.sqlite"))
    p.add_argument("--sample", default=str(REPO / "ios" / "Resources" / "dictionary-sample.sqlite"))
    p.set_defaults(fn=cmd_build)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
