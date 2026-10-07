"""Fail on tracked files that make every clone and CI checkout heavy (#42).

GitHub warns on any file over 50 MB and refuses one over 100 MB. In
September 2026 three Sketchfab robots sat at 41 to 66 MB; #102 and #143
shrank them below 25 MB. The bigger weight was never the models, though:
on 2026-10-08 the tree carried 1.44 GB of 3840x2400 PNG screenshots under
docs/screenshots, 1.2 GB of them frame dumps from the capture tools that
nothing referenced, all downloaded by each of the three CI jobs.

Two budgets:
  * any tracked file:            50 MB  (GitHub's warning threshold)
  * any tracked still in docs/:   3 MB  (a 1600 px wide PNG is 1-2 MB;
                                         shrink with tools/shrink_screenshots.py)

    python tools/check_large_files.py               # tracked files, working tree
    python tools/check_large_files.py --rev <rev>   # a commit's tree, from git
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MB = 1024 * 1024
MAX_FILE = 50 * MB
MAX_DOC_IMAGE = 3 * MB
# Stills only: the capture tools save stills at window size (3840x2400 on the
# dev machine). The two GIFs in docs/diagrams are hand-assembled at 720 px.
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tga")


def git(*args) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=True).stdout


def sizes(rev):
    if rev:
        for line in git("ls-tree", "-r", "-l", "--full-tree", rev).splitlines():
            meta, path = line.split("\t", 1)
            kind, size = meta.split()[1], meta.split()[3]
            if kind == "blob":
                yield path, int(size)
        return
    for path in git("ls-files").splitlines():
        full = os.path.join(ROOT, path)
        if os.path.isfile(full):
            yield path, os.path.getsize(full)


def main() -> int:
    rev = None
    if len(sys.argv) == 3 and sys.argv[1] == "--rev":
        rev = sys.argv[2]
    elif len(sys.argv) != 1:
        print(__doc__)
        return 2
    errors = []
    for path, size in sizes(rev):
        if size > MAX_FILE:
            errors.append("%s: %.1f MB, over the %d MB per-file limit" % (path, size / MB, MAX_FILE // MB))
        elif path.startswith("docs/") and path.lower().endswith(IMAGE_EXT) and size > MAX_DOC_IMAGE:
            errors.append("%s: %.1f MB, over the %d MB docs-image limit (tools/shrink_screenshots.py)"
                          % (path, size / MB, MAX_DOC_IMAGE // MB))
    if errors:
        print("Oversized tracked files: %d" % len(errors))
        for e in errors:
            print("  " + e)
        return 1
    print("Oversized tracked files: none")
    return 0


if __name__ == "__main__":
    sys.exit(main())
