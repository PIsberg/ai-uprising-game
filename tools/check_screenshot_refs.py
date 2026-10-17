"""Fail on a tracked still in docs/screenshots/ that no doc references.

The README gallery stills are the only screenshots the repo tracks; every
capture tool writes to a gitignored subfolder. A still nothing shows is weight
every checkout downloads for nothing: the README refresh untracked 11 of them,
and four promo scripts kept writing those names back into docs/screenshots/
where a `git add -A` would commit them again (#272).

A still counts as referenced when its path relative to docs/ (e.g.
`screenshots/armory.png`) appears in any tracked .md or .html file.

    python tools/check_screenshot_refs.py
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def tracked(*patterns: str) -> list:
    out = subprocess.run(["git", "ls-files", "--", *patterns], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout
    return [p for p in out.splitlines() if p]


def main() -> int:
    stills = [p for p in tracked("docs/screenshots/*.png", "docs/screenshots/*.jpg")
              if p.count("/") == 2]   # top level only; subfolders are gitignored tool output
    docs = ""
    for rel in tracked("*.md", "*.html"):
        path = os.path.join(ROOT, rel)
        if os.path.isfile(path):
            with open(path, encoding="utf-8", errors="replace") as f:
                docs += f.read()
    unreferenced = [p for p in stills if p[len("docs/"):] not in docs]
    if unreferenced:
        print("%d tracked still(s) in docs/screenshots/ that no .md or .html references:" % len(unreferenced))
        for p in unreferenced:
            print("  " + p)
        print("Delete them (git rm), or reference them from README.md or docs/.")
        return 1
    print("screenshot refs OK: %d tracked stills, all referenced" % len(stills))
    return 0


if __name__ == "__main__":
    sys.exit(main())
