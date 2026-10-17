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

Also fails on any one-time coaching hint (GameState.teach_once: a literal, a
same-file constant, or a MECHANIC_HINTS/ELITE_HINTS value) with no row: the
HUD toast translates them, and until #317 none of the 30-odd hints had one.

Also fails on any story string with no row (#236): each StoryArc beat's
tagline, trace and lead, the act names, the overlord's act lines, the HUD's
taunt pools and the format strings the briefing, HUD and credits build.

Also fails on any skirmish toast (GameState.skirmish_event.emit anywhere under
scripts/: a literal title, either side of a `"A" if c else "B"` title, and a
literal or tr() description) with no row. The HUD shows `tr(title) - tr(desc)`;
until #331 a dozen toasts had no row, and three formatted their number into the
English text before tr() saw it, so no row could ever have matched.

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
    ("scripts/systems/intercept_courier.gd", r'var base_label: String = "([^"]+)"'),
    ("scripts/systems/intercept_courier.gd", r'skirmish_event\.emit\("([^"]+)"'),
    ("scripts/systems/firewall_barrier.gd", r'skirmish_event\.emit\("([^"]+)"'),
    ("scripts/systems/firewall_barrier.gd", r'else "([^"]+)"\)'),
    # a survive wave's flood alerts (HUD skirmish toast) and their defaults
    ("scripts/levels/level_defs.gd", r'"(?:warn|drain)_(?:title|text)":\s*"((?:[^"\\]|\\.)+)"'),
    ("scripts/systems/flood_surge.gd", r'var (?:warn|drain)_(?:title|text): String = "([^"]+)"'),
    # a survive wave's weather alerts (level defs share the warn_* pattern above)
    ("scripts/levels/level_defs.gd", r'"clear_(?:title|text)":\s*"((?:[^"\\]|\\.)+)"'),
    ("scripts/systems/weather_shift.gd", r'var (?:warn|clear)_(?:title|text): String = "([^"]+)"'),
    # kill switches: default label, the watchdog's toasts (title and text), the
    # revert lines it cycles through, and the switch's own Label3D tags
    ("scripts/systems/kill_switch_bank.gd", r'var base_label: String = "([^"]+)"'),
    ("scripts/systems/kill_switch_bank.gd", r'skirmish_event\.emit\("([^"]+)"'),
    ("scripts/systems/kill_switch_bank.gd", r'skirmish_event\.emit\("[^"]+", "([^"]+)"'),
    ("scripts/systems/kill_switch_bank.gd", r'REVERT_TITLE := "([^"]+)"'),
    ("scripts/systems/kill_switch_bank.gd", r'(?m)^\t"([^"]+)",\r?$'),
    ("scripts/systems/kill_switch.gd", r'"(KILL SWITCH|OFF)"'),
    # hallucinated keycards: the toast title, its cycled lines and the decoy tag
    ("scripts/systems/keycard.gd", r'HALLUCINATION_TITLE := "([^"]+)"'),
    ("scripts/systems/keycard.gd", r'(?m)^\t"([^"]+)",\r?$'),
    ("scripts/systems/keycard.gd", r'_tag\.text = "([^"]+)"'),
    # the ALIGNED escort: default label, its state words, toasts and unit tag
    ("scripts/systems/aligned_escort.gd", r'var base_label: String = "([^"]+)"'),
    ("scripts/systems/aligned_escort.gd", r'"(?:down|moving|waiting)": "([^"]+)"'),
    ("scripts/systems/aligned_escort.gd", r'skirmish_event\.emit\("([^"]+)"'),
    ("scripts/systems/aligned_escort.gd", r'skirmish_event\.emit\("[^"]+", "([^"]+)"'),
    ("scripts/systems/aligned_escort.gd", r'_tag\.text = "([^"]+)"'),
    # the optional bonus objective: HUD tag and its toasts (labels are "label" in the defs)
    ("scripts/ui/hud.gd", r'tr\("(BONUS)"\)'),
    ("scripts/autoload/game_state.gd", r'skirmish_event\.emit\("(BONUS [A-Z]+)"'),
    # the story (#236): every beat's briefing tagline, trace log and SECTOR
    # CLEARED lead, the act names, the overlord's act lines and the HUD's
    # ambient taunts, plus the formats the briefing, HUD and credits build
    ("scripts/systems/story_arc.gd", r'"(?:tagline|trace|lead)":\s*"((?:[^"\\]|\\.)+)"'),
    ("scripts/systems/story_arc.gd", r'translate\("([^"]+)"\)'),
    ("scripts/ui/hud.gd", r'tr\("(◆ LEAD: %s)"\)'),
    ("scripts/cutscene/level_comic_briefing.gd", r'tr\("(◆ THE 03:14 TRACE · LOG %d/%d)"\)'),
    ("scripts/ui/credits.gd", r'"text": "(THE 03:14 TRACE)"'),
]


# (file, const) pairs: every string literal in that constant array is shown
# through tr() (the story's act names and overlord pools, the HUD's taunts).
CONST_ARRAYS = [
    ("scripts/systems/story_arc.gd", "ACTS"),
    ("scripts/systems/story_arc.gd", "OVERLORD_LINES"),
    ("scripts/ui/hud.gd", "OVERLORD_TAUNTS"),
    ("scripts/ui/hud.gd", "OVERLORD_BOSS"),
    ("scripts/ui/hud.gd", "OVERLORD_LOWHP"),
    ("scripts/ui/hud.gd", "OVERLORD_RATTLED"),
]


def required_labels() -> dict:
    """Map each label the HUD translates to the first file that authors it."""
    out = {}
    for rel, pattern in LABEL_SOURCES:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
            src = f.read()
        for m in re.finditer(pattern, src):
            out.setdefault(m.group(1).replace('\\"', '"'), rel)
    for rel, name in CONST_ARRAYS:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
            src = f.read()
        block = re.search(r"const %s\b[^=]*= \[(.*?)\n\]" % name, src, re.S)
        if block is None:
            out.setdefault("<const %s not found>" % name, rel)
            continue
        for s in re.findall(r'"((?:[^"\\]|\\.)+)"', block.group(1)):
            out.setdefault(s.replace('\\"', '"'), rel)
    return out


# One-time coaching hints (GameState.teach_once -> HUD toast, through tr()).
# A hint argument is a string literal (possibly on the next line), a constant
# in the same file, or a lookup into one of these hint dictionaries.
HINT_DICTS = ("MECHANIC_HINTS", "ELITE_HINTS")


def _dict_values(src: str, name: str) -> list:
    m = re.search(r"const %s := \{(.*?)\n\}" % name, src, re.S)
    return re.findall(r'"[a-z_]+":\s*"((?:[^"\\]|\\.)+)"', m.group(1)) if m else []


def teach_hints() -> dict:
    """Map each teach-hint text to the file that authors it."""
    out = {}
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "scripts")):
        for fn in files:
            if not fn.endswith(".gd"):
                continue
            path = os.path.join(dirpath, fn)
            rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
            with open(path, encoding="utf-8") as f:
                src = f.read()
            for m in re.finditer(r'teach_once\(\s*[^,()]+,\s*(?:tr\()?("((?:[^"\\]|\\.)+)"|[A-Z_][A-Z0-9_]*)', src):
                if m.group(2) is not None:
                    out.setdefault(m.group(2), rel)
                    continue
                const = re.search(r'const %s := "((?:[^"\\]|\\.)+)"' % m.group(1), src)
                if const:
                    out.setdefault(const.group(1), rel)
            for name in HINT_DICTS:
                if ("teach_once(" in src or "teach_elite" in src) and ("const %s" % name) in src:
                    for v in _dict_values(src, name):
                        out.setdefault(v, rel)
    return out


# GameState.skirmish_event.emit("TITLE" [if c else "TITLE2"], [tr(]"desc"...),
# where \s spans the line break of a call split over two lines.
_EMIT = re.compile(
    r'skirmish_event\.emit\(\s*"((?:[^"\\]|\\.)+)"'
    r'(?:\s+if\s+[^,"]+?\s+else\s+"((?:[^"\\]|\\.)+)")?'
    r'(?:\s*,\s*(?:tr\()?"((?:[^"\\]|\\.)+)")?')
# a helper that forwards its literals to the toast (HaulPayload._drop)
_FORWARDS = re.compile(r'\b_drop\([^,()]+(?:\([^()]*\))?[^,()]*,\s*"([^"]+)",\s*"([^"]+)"\)')


def skirmish_toasts() -> dict:
    """Map each literal skirmish toast title/description to the file that emits it."""
    out = {}
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "scripts")):
        for fn in files:
            if not fn.endswith(".gd"):
                continue
            path = os.path.join(dirpath, fn)
            rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
            with open(path, encoding="utf-8") as f:
                src = f.read()
            for pattern in (_EMIT, _FORWARDS):
                for m in pattern.finditer(src):
                    for s in m.groups():
                        if s:
                            out.setdefault(s.replace('\\"', '"'), rel)
    return out


def main() -> int:
    # The hints carry symbols (◆ ✦ ☠) a Windows cp1252 console cannot print.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
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
    for hint, rel in sorted(teach_hints().items()):
        if hint not in seen:
            errors.append("no row for teach hint %r (%s)" % (hint, rel))
    for toast, rel in sorted(skirmish_toasts().items()):
        if toast not in seen:
            errors.append("no row for skirmish toast %r (%s)" % (toast, rel))
    if errors:
        print("strings.csv: %d problem(s)" % len(errors))
        for e in errors:
            print("  " + e)
        return 1
    print("strings.csv OK: %d keys, %d languages" % (len(seen), len(header) - 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
