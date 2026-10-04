"""Keep assets/i18n/strings.csv parseable. The file uses English text as the
translation key, so a line with an unquoted comma does not fail anything: the
row just splits into extra columns and Godot quietly keys it by the fragment
before the comma, or shifts every later language one column over. Two rows
shipped that way from the first localization commit until 2026-10-04 (the
intro comic's "For years, the machines served us." never translated, and the
"At 03:14" line put French text under German).

Fails (exit 1) on any row whose column count differs from the header, any key
that differs from its `en` cell, and any duplicate key.

Also fails on any task, wave or firewall `"label"` authored in
scripts/levels/level_defs.gd, or any default label the builder and task objects
fall back to, that has no row: the HUD passes them through tr(), which returns
the English key unchanged when the row is missing, so es/fr/de/pt players see
English mid-mission and nothing else notices (64 of 78 labels, 2026-10-04).

    python tools/check_strings_csv.py
"""
import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV = os.path.join(ROOT, "assets", "i18n", "strings.csv")

# (file, regex) pairs whose first group is a string the HUD shows through tr().
LABEL_SOURCES = [
    # every "label": "..." in the level defs (tasks, survive waves, firewalls)
    ("scripts/levels/level_defs.gd", r'"label":\s*"((?:[^"\\]|\\.)+)"'),
    # builder fallbacks: t.get("label", "Hack the terminal")
    ("scripts/levels/level_builder.gd", r'get\("label",\s*"((?:[^"\\]|\\.)+)"\)'),
    # task objects' own default labels and fallback banners
    ("scripts/systems/escape_zone.gd", r'var base_label: String = "([^"]+)"'),
    ("scripts/systems/haul_payload.gd", r'var base_label: String = "([^"]+)"'),
    ("scripts/systems/firewall_barrier.gd", r'skirmish_event\.emit\("([^"]+)"'),
    ("scripts/systems/firewall_barrier.gd", r'else "([^"]+)"\)'),
]


def required_labels() -> dict:
    """Map each label the HUD translates to the first file that authors it."""
    out = {}
    for rel, pattern in LABEL_SOURCES:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
            src = f.read()
        for m in re.finditer(pattern, src):
            out.setdefault(m.group(1).replace('\\"', '"'), rel)
    return out


def main() -> int:
    with open(CSV, encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    header = rows[0]
    en = header.index("en")
    errors = []
    seen = {}
    for line, row in enumerate(rows[1:], start=2):
        if not row:
            continue
        if len(row) != len(header):
            errors.append("line %d: %d columns, header has %d (unquoted comma?): %r"
                          % (line, len(row), len(header), row[0]))
            continue
        if row[0] != row[en]:
            errors.append("line %d: key %r differs from its en cell %r" % (line, row[0], row[en]))
        if row[0] in seen:
            errors.append("line %d: duplicate key %r (first on line %d)" % (line, row[0], seen[row[0]]))
        seen[row[0]] = line
    for label, rel in sorted(required_labels().items()):
        if label not in seen:
            errors.append("no row for label %r (%s)" % (label, rel))
    if errors:
        print("strings.csv: %d problem(s)" % len(errors))
        for e in errors:
            print("  " + e)
        return 1
    print("strings.csv OK: %d keys, %d languages" % (len(seen), len(header) - 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
