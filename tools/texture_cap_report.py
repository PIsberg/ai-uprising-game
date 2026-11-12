"""Score the frames tools/texture_cap_ab.tscn saved: what a texture cap changes on screen (#56).

For every model, distance and view there are four frames: `o` (the textures as
imported, block-compressed, what ships), `a` (rebuilt at full size, uncompressed),
`b` (rebuilt capped) and `a2` (`a` again). Three comparisons, each over the
pixels the model covers, since the flat background would flatter every number:
  cap    `a` against `b`: what the cap changes, resolution alone
  noise  `a` against `a2`: what the renderer changes by itself between captures
  bc     `o` against `a`: what block compression already costs today, as a
         yardstick. A cap that changes less than this is under what ships now.

    python tools/texture_cap_report.py <dir>            # table + <dir>/sheet_<model>_x<dist>_<view>.png
    python tools/texture_cap_report.py <dir> --no-sheets

Columns: PSNR in dB (99 = identical), p99 = the 99th percentile of the largest
per-channel difference on a 0-255 scale, >8 = share of the model's pixels that
moved by more than 8 of 255. A sheet is the full-size frame beside the capped
one, cropped to the 600 px window where they differ most.
"""
import glob
import os
import re
import sys

import numpy as np
from PIL import Image

WINDOW = 600


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)


def score(x, y, subject):
    diff = np.abs(x - y).max(axis=2)[subject]
    mse = ((x - y).astype(np.float32) ** 2)[subject].mean()
    psnr = 99.0 if mse == 0 else min(99.0, 10 * np.log10(255.0 ** 2 / mse))
    return psnr, float(np.percentile(diff, 99)), float((diff > 8).mean() * 100)


def worst_window(x, y):
    diff = np.abs(x - y).max(axis=2).astype(np.float32)
    best = (0, 0, -1.0)
    for top in range(0, max(diff.shape[0] - WINDOW, 1), 100):
        for left in range(0, max(diff.shape[1] - WINDOW, 1), 100):
            total = diff[top:top + WINDOW, left:left + WINDOW].sum()
            if total > best[2]:
                best = (left, top, total)
    return best[0], best[1]


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        print(__doc__)
        return 2
    folder = args[0]
    sheets = "--no-sheets" not in sys.argv
    frames = sorted(glob.glob(os.path.join(folder, "*_a.png")))
    if not frames:
        print(f"no frames in {folder}: run tools/texture_cap_ab.tscn with out={folder} first")
        return 1
    print("%-24s %5s %-5s %8s | %-24s | %-9s | %-24s" % ("model", "dist", "view", "subject", "cap: PSNR  p99    >8", "noise", "bc: PSNR  p99    >8"))
    over = 0
    for path in frames:
        m = re.match(r"(.+)_x([0-9.]+)_([a-z0-9]+)_a\.png$", os.path.basename(path))
        if not m:
            continue
        model, dist, view = m.groups()
        a, b, a2 = load(path), load(path[:-6] + "_b.png"), load(path[:-6] + "_a2.png")
        subject = np.abs(a - a[0, 0]).max(axis=2) > 6
        if not subject.any():
            continue
        rows = np.where(subject.any(axis=1))[0]
        cap, noise = score(a, b, subject), score(a, a2, subject)
        bc = score(load(path[:-6] + "_o.png"), a, subject)
        flag = ""
        if cap[0] < min(noise[0], bc[0]):
            over += 1
            flag = "  <- more than compression costs"
        print("%-24s %5s %-5s %5d px | %5.1f dB  %3.0f  %5.2f%%   | %5.1f dB  | %5.1f dB  %3.0f  %5.2f%%%s"
              % (model, "x" + dist, view, rows[-1] - rows[0] + 1, cap[0], cap[1], cap[2], noise[0], bc[0], bc[1], bc[2], flag))
        if sheets and cap[0] < 99.0:
            left, top = worst_window(a, b)
            box = (left, top, left + WINDOW, top + WINDOW)
            sheet = Image.new("RGB", (WINDOW * 2 + 8, WINDOW), (255, 0, 255))
            sheet.paste(Image.open(path).convert("RGB").crop(box), (0, 0))
            sheet.paste(Image.open(path[:-6] + "_b.png").convert("RGB").crop(box), (WINDOW + 8, 0))
            sheet.save(os.path.join(folder, f"sheet_{model}_x{dist}_{view}.png"))
    print(f"{over} of {len(frames)} shots change by more than block compression already does")
    return 0


if __name__ == "__main__":
    sys.exit(main())
