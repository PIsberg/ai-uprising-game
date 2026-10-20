"""Fail on a tracked script or shader without its tracked .uid, or the reverse.

Godot 4.4+ writes a `<file>.uid` sidecar beside every .gd and .gdshader the
first time it imports one, holding the resource's stable `uid://` id. A scene
saved in the editor references the script by that id first and the path
second, so a sidecar left uncommitted gets a fresh random id on every other
checkout, and the two machines save scenes that disagree. On 2026-10-20, 9 of
808 tracked scripts had no tracked sidecar (left as untracked files in the
main tree by six separate commits), and 4 tracked sidecars outlived the
script they named.

Fails (exit 1) when a tracked .gd/.gdshader has no tracked .uid beside it, or
a tracked .uid has no tracked file it belongs to. To fix the first, run
`godot --headless --path . --import` and commit the new .uid; for the second,
delete the stale .uid.

    python tools/check_script_uids.py
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_EXT = (".gd", ".gdshader")


def tracked() -> set:
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True)
    return {p for p in out.stdout.splitlines() if p}


def main() -> int:
    files = tracked()
    errors = []
    for p in sorted(files):
        if p.endswith(SOURCE_EXT) and p + ".uid" not in files:
            errors.append("%s: no tracked %s.uid (run an import and commit it)" % (p, os.path.basename(p)))
        if p.endswith(".uid") and p[:-len(".uid")] not in files:
            errors.append("%s: stale, %s is not tracked" % (p, p[:-len(".uid")]))
    if errors:
        print("Script uid sidecars: %d problem(s)" % len(errors))
        for e in errors:
            print("  " + e)
        return 1
    print("Script uid sidecars: every .gd/.gdshader has one, none stale")
    return 0


if __name__ == "__main__":
    sys.exit(main())
