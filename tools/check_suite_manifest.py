"""Keep the probe suite honest: tools/probes.txt is the one list both runners
read, and tests/README.md is the index that says which probes are `suite`.
The two must agree, every listed scene must exist, and nothing may be listed
twice. Exit 1 with a precise diff otherwise (run in CI before the suite).

Also checks the sentence above the index table, which quotes a probe count per
mode. Those four numbers were unenforced and drifted: they read "244 total, 30
suite" against a table holding 264 rows and 46 suite probes (#108).

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


# The header sentence wraps across lines, so match against whitespace-collapsed
# text rather than trying to anchor each number to a line.
HEADER_FIELDS = (
    ("total", r"(\d+) probes total:"),
    ("suite", r"\*\*(\d+)\*\* wired into the headless suite"),
    ("headless", r"\*\*(\d+)\*\* headless-capable"),
    ("windowed", r"\*\*(\d+)\*\* windowed-only"),
)


def readme_header_counts(problems):
    """The four numbers the index sentence claims, or None if it cannot be read.

    A header this check cannot parse is reported, never skipped: silently
    passing is how the old numbers went 20 out of date without anyone noticing.
    """
    flat = re.sub(r"\s+", " ", open(README, encoding="utf-8").read())
    found = {}
    for key, pattern in HEADER_FIELDS:
        m = re.search(pattern, flat)
        if m is None:
            problems.append(
                "tests/README.md: cannot find the %s count in the index sentence "
                "(expected /%s/) - if the wording changed, update HEADER_FIELDS "
                "in this script so the numbers stay checked" % (key, pattern)
            )
            return None
        found[key] = int(m.group(1))
    return found


def check_header(rows_by_mode, problems):
    claimed = readme_header_counts(problems)
    if claimed is None:
        return
    actual = dict(rows_by_mode)
    actual["total"] = sum(rows_by_mode.values())
    for key, _ in HEADER_FIELDS:
        if claimed[key] != actual[key]:
            problems.append(
                "tests/README.md says %d %s probes, the index table has %d"
                % (claimed[key], key, actual[key])
            )


def readme_rows_by_mode():
    text = open(README, encoding="utf-8").read()
    rows = re.findall(r"^\|\s*[A-Za-z_0-9]+\s*\|.*\|\s*(suite|headless|windowed)\s*\|\s*$", text, re.M)
    counts = {"suite": 0, "headless": 0, "windowed": 0}
    for kind in rows:
        counts[kind] += 1
    return counts


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
    check_header(readme_rows_by_mode(), problems)
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
