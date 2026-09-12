"""Keep the probe suite honest: tools/probes.txt is the one list both runners
read, and tests/README.md is the index that says which probes are `suite`.
The two must agree, every listed scene must exist, and nothing may be listed
twice. Exit 1 with a precise diff otherwise (run in CI before the suite).

    python tools/check_suite_manifest.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "tools", "probes.txt")
README = os.path.join(ROOT, "tests", "README.md")


def manifest_entries():
    out = []
    for raw in open(MANIFEST, encoding="utf-8"):
        line = raw.split("#", 1)[0].strip()
        if line:
            out.append(line)
    return out


def readme_rows():
    text = open(README, encoding="utf-8").read()
    rows = re.findall(r"^\|\s*([A-Za-z_0-9]+)\s*\|.*\|\s*(suite|headless|windowed)\s*\|\s*$", text, re.M)
    return {n for n, kind in rows if kind == "suite"}, {n for n, _ in rows}


def main() -> int:
    problems = []
    names = []
    for e in manifest_entries():
        m = re.fullmatch(r"res://tests/([A-Za-z_0-9]+)\.tscn", e)
        if not m:
            problems.append(f"manifest entry is not a res://tests/<name>.tscn path: {e}")
            continue
        names.append(m.group(1))
        if not os.path.exists(os.path.join(ROOT, "tests", m.group(1) + ".tscn")):
            problems.append(f"manifest lists a scene that does not exist: {e}")
    dups = sorted({n for n in names if names.count(n) > 1})
    if dups:
        problems.append("manifest lists twice: " + ", ".join(dups))
    suite, indexed = readme_rows()
    for n in sorted(set(names) - suite):
        where = "marks it headless/windowed" if n in indexed else "has no row for it"
        problems.append(f"{n} is in tools/probes.txt but tests/README.md {where} - mark it `suite`")
    for n in sorted(suite - set(names)):
        problems.append(f"{n} is marked `suite` in tests/README.md but missing from tools/probes.txt")
    if problems:
        print("suite manifest check FAILED:")
        for p in problems:
            print("  -", p)
        return 1
    print(f"suite manifest OK: {len(names)} probes, tests/README.md agrees")
    return 0


if __name__ == "__main__":
    sys.exit(main())
