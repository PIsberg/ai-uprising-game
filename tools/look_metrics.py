"""Score the eye-level level screenshots written by tests/look_capture.tscn.

Usage:  python tools/look_metrics.py <dir-with-<level>.png> [<baseline dir>]

Per frame it reports the numbers a visual audit keeps arguing about, so a
before/after comparison is a diff of a table instead of two people squinting:

  luma    mean Rec.709 luminance (0-1)          dark frames < ~0.10
  std     luminance spread (contrast)           flat frames < ~0.12
  p5/p95  5th / 95th luminance percentile       both low = crushed, both high = washed
  black%  pixels darker than 0.02               dead-void share
  white%  pixels brighter than 0.98             blown-out share
  sat     mean HSV saturation                   grey frames < ~0.15
  hue_H   hue entropy (bits, sat-weighted)      mono frames < ~2.0; varied > ~3.0
  sharp   variance of the Laplacian on luma     soft/hazy frames low relative to the run
  hue     dominant hue bucket name

Thresholds are heuristics from the 2026-07 and 2026-09 audits, not gates; the
script flags outliers but the call is made by looking at the frame.
"""
import sys, os, math
import numpy as np
from PIL import Image

HUE_NAMES = ["red", "orange", "yellow", "green", "teal", "cyan", "blue", "violet", "magenta", "pink"]


def analyse(path):
    im = Image.open(path).convert("RGB")
    if im.width > 960:
        im = im.resize((960, round(im.height * 960 / im.width)), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255.0
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
    mx = a.max(axis=2); mn = a.min(axis=2)
    delta = mx - mn
    sat = np.where(mx > 1e-4, delta / np.maximum(mx, 1e-4), 0.0)
    # hue in [0,1)
    hue = np.zeros_like(mx)
    m = delta > 1e-4
    rc = np.where(m, (mx - r) / np.maximum(delta, 1e-4), 0)
    gc = np.where(m, (mx - g) / np.maximum(delta, 1e-4), 0)
    bc = np.where(m, (mx - b) / np.maximum(delta, 1e-4), 0)
    h = np.where(r == mx, bc - gc, np.where(g == mx, 2.0 + rc - bc, 4.0 + gc - rc))
    hue = np.where(m, (h / 6.0) % 1.0, 0.0)
    w = sat * (luma > 0.03)
    hist, _ = np.histogram(hue, bins=10, range=(0, 1), weights=w)
    p = hist / max(hist.sum(), 1e-6)
    ent = -float(np.sum(p[p > 0] * np.log2(p[p > 0])))
    dom = HUE_NAMES[int(np.argmax(hist))] if hist.sum() > 0 else "grey"
    # Laplacian sharpness on luma
    L = luma
    lap = -4 * L[1:-1, 1:-1] + L[:-2, 1:-1] + L[2:, 1:-1] + L[1:-1, :-2] + L[1:-1, 2:]
    sharp = float(lap.var() * 1e3)
    return dict(
        luma=float(luma.mean()), std=float(luma.std()),
        p5=float(np.percentile(luma, 5)), p95=float(np.percentile(luma, 95)),
        black=float((luma < 0.02).mean() * 100), white=float((luma > 0.98).mean() * 100),
        sat=float(sat.mean()), hue_H=ent, sharp=sharp, hue=dom,
    )


def flags(m, sharp_median):
    f = []
    if m["luma"] < 0.10: f.append("DARK")
    if m["luma"] > 0.55: f.append("BRIGHT")
    if m["std"] < 0.12: f.append("FLAT")
    if m["black"] > 35: f.append("VOID")
    if m["white"] > 8: f.append("BLOWN")
    if m["sat"] < 0.15: f.append("GREY")
    if m["hue_H"] < 2.0: f.append("MONO")
    if sharp_median > 0 and m["sharp"] < 0.35 * sharp_median: f.append("SOFT")
    return ",".join(f)


def main():
    d = sys.argv[1]
    base = sys.argv[2] if len(sys.argv) > 2 else None
    rows = []
    for fn in sorted(os.listdir(d)):
        if fn.endswith(".png"):
            rows.append((fn[:-4], analyse(os.path.join(d, fn))))
    if not rows:
        print("no png frames in", d); return
    med = float(np.median([m["sharp"] for _, m in rows]))
    hdr = f"{'level':12} {'luma':>5} {'std':>5} {'p5':>5} {'p95':>5} {'blk%':>5} {'wht%':>5} {'sat':>5} {'hueH':>5} {'sharp':>6} {'hue':8} flags"
    print(hdr)
    for name, m in rows:
        line = (f"{name:12} {m['luma']:5.2f} {m['std']:5.2f} {m['p5']:5.2f} {m['p95']:5.2f} "
                f"{m['black']:5.1f} {m['white']:5.1f} {m['sat']:5.2f} {m['hue_H']:5.2f} {m['sharp']:6.2f} {m['hue']:8} {flags(m, med)}")
        if base and os.path.exists(os.path.join(base, name + ".png")):
            b = analyse(os.path.join(base, name + ".png"))
            line += f"   | was luma {b['luma']:.2f} std {b['std']:.2f} sat {b['sat']:.2f} hueH {b['hue_H']:.2f} sharp {b['sharp']:.2f}"
        print(line)


if __name__ == "__main__":
    main()
