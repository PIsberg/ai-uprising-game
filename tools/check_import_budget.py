"""Fail when the imported assets a release ships grow past their budget (#56).

The release pack is almost entirely `.godot/imported`: 341 of 343 MB on
2026-10-08. This sums the imported files of every tracked `.import` whose
source the export ships (everything outside the export's exclude_filter:
tests/, tools/, docs/), so build size is checked in CI after the import step
instead of only when someone runs tools/build_release.ps1 by hand.

Two budgets, both a ratchet: lower them when an asset pass lands, raise them
only on purpose, in the same commit as the asset that needs it.
  * all shipped imports together: TOTAL_BUDGET
  * any single imported file:      FILE_BUDGET

Also fails on a tracked `.import` whose source file is gone: a screenshot a
probe once saved into res:// leaves its stub behind (16 at the project root on
2026-10-08), and the editor re-imports nothing for it.

    python tools/check_import_budget.py     # needs a populated .godot (run --import first)
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MB = 1024 * 1024
TOTAL_BUDGET = 309 * MB  # 2026-10-08: MANUS decimated, 308.9 -> 305.2 MB
FILE_BUDGET = 40 * MB
EXCLUDED = ("tests/", "tools/", "docs/")  # export_presets.cfg exclude_filter
DEST = re.compile(r'^dest_files=\[(.*)\]', re.MULTILINE)


def main() -> int:
    out = subprocess.run(["git", "ls-files", "*.import"], cwd=ROOT, capture_output=True, text=True, check=True)
    total = 0
    missing = []
    rows = []
    stale = []
    for imp in out.stdout.splitlines():
        src = imp[: -len(".import")]
        if not os.path.isfile(os.path.join(ROOT, src)):
            stale.append(imp)
            continue
        if src.startswith(EXCLUDED):
            continue
        with open(os.path.join(ROOT, imp), encoding="utf-8") as f:
            m = DEST.search(f.read())
        if not m:
            continue
        size = 0
        for dest in re.findall(r'"res://([^"]+)"', m.group(1)):
            full = os.path.join(ROOT, dest)
            if os.path.isfile(full):
                size += os.path.getsize(full)
            else:
                missing.append(dest)
        total += size
        rows.append((size, src))
    if missing:
        print("Import budget: %d imported file(s) missing; run `godot --headless --path . --import` first" % len(missing))
        for d in missing[:10]:
            print("  " + d)
        return 1
    rows.sort(reverse=True)
    errors = ["%s: tracked, but its source file is gone (git rm it)" % s for s in stale]
    if total > TOTAL_BUDGET:
        errors.append("shipped imports total %.1f MB, budget %d MB" % (total / MB, TOTAL_BUDGET // MB))
    for size, src in rows:
        if size > FILE_BUDGET:
            errors.append("%s imports to %.1f MB, per-file budget %d MB" % (src, size / MB, FILE_BUDGET // MB))
    print("Import budget: %.1f MB shipped across %d assets (budget %d MB); largest:"
          % (total / MB, len(rows), TOTAL_BUDGET // MB))
    for size, src in rows[:5]:
        print("  %6.1f MB  %s" % (size / MB, src))
    if errors:
        print("Failed:")
        for e in errors:
            print("  " + e)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
