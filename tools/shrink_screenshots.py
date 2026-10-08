"""Downscale docs screenshots to the size the README gallery shows them at.

The capture tools (tests/promo_*.gd, tools/capture_*.gd) save at window size,
3840x2400 on the dev machine: 5 to 13 MB per PNG. The gallery shows each image
in a half-width table cell, so 1600 px wide is plenty, at 1 to 2 MB.
tools/check_large_files.py fails CI on a docs still over 3 MB.

Resizes in place (Lanczos) and keeps the file name and format, so nothing that
references the image changes.

    python tools/shrink_screenshots.py                  # every tracked docs still over budget
    python tools/shrink_screenshots.py <file> [...]     # just these
"""
import os
import subprocess
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAX_WIDTH = 1600
BUDGET = 3 * 1024 * 1024
STILLS = (".png", ".jpg", ".jpeg", ".webp")


def over_budget() -> list:
    out = subprocess.run(["git", "ls-files", "docs"], cwd=ROOT, capture_output=True, text=True, check=True)
    paths = [os.path.join(ROOT, p) for p in out.stdout.splitlines() if p.lower().endswith(STILLS)]
    return [p for p in paths if os.path.isfile(p) and os.path.getsize(p) > BUDGET]


def shrink(path: str) -> None:
    before = os.path.getsize(path)
    im = Image.open(path)
    im.load()
    if im.width > MAX_WIDTH:
        im = im.resize((MAX_WIDTH, round(im.height * MAX_WIDTH / im.width)), Image.LANCZOS)
    if path.lower().endswith((".jpg", ".jpeg")):
        im.convert("RGB").save(path, quality=88)
    else:
        im.save(path, optimize=True)
    print("%s: %d x %d, %.1f -> %.1f MB" % (os.path.relpath(path, ROOT), im.width, im.height,
                                            before / 2**20, os.path.getsize(path) / 2**20))


def main() -> int:
    paths = sys.argv[1:] or over_budget()
    for p in paths:
        shrink(p)
    if not paths:
        print("no docs stills over budget")
    return 0


if __name__ == "__main__":
    sys.exit(main())
