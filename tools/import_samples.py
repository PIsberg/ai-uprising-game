"""Import CC0 sample packs as level-matched sound-id overrides.

AudioBus plays assets/audio/samples/<id>.ogg instead of the synth sound <id>, and
<id>_0.ogg .. <id>_7.ogg as no-repeat random variants. A raw drop-in changes the
mix: a Kenney impact is ~10 dB hotter or quieter than the synth it replaces, and
every caller's volume_db was tuned against the synth. This tool measures both and
bakes the gain into the file, so a sample lands at the synth's loudness.

Loudness = the loudest 50 ms RMS window (short one-shots are too brief for LUFS).
The synth is dense (little headroom between its RMS and its peak) and the packs
are dynamic, so a plain gain either clips or lands up to 5 dB short: the gain is
followed by a -1 dBFS limiter instead, and the encoded file is measured again
(the "out" column) so the match is checked, not assumed. Output is mono (every
world sound is positional) Ogg Vorbis q4, 44.1 kHz.

    godot --headless --path . --audio-driver Dummy res://tools/dump_synth.tscn -- --out=<synth dir>
    python tools/import_samples.py --packs <dir with the unzipped packs> --synth <synth dir>

Packs (CC0, https://kenney.nl): "Sci-Fi Sounds" 1.0 unzipped to <packs>/scifi,
"Impact Sounds" 1.0 unzipped to <packs>/impact. Credited in CREDITS.md.
Needs ffmpeg on PATH and numpy.
"""
import argparse
import glob
import os
import subprocess
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio", "samples")
RATE = 44100
MAX_VARIANTS = 8
LIMIT = 0.891  # -1 dBFS, linear, for ffmpeg's alimiter
GAIN_CAP_DB = 18.0
MATCH_DB = 1.5  # a take that cannot get this close to the synth is dropped, not squashed
MIN_VARIANTS = 3  # fewer surviving takes than this fails the run

# sound id -> (pack, file stem); every numbered take of the stem becomes a variant.
# Only ids with a pack sound that fits: no kinetic gunshots or music exist in these
# packs, so pistol/rifle/shotgun fire and the music tracks stay synthesized.
MAPPING = {
    "impact_metal": ("impact", "impactMetal_medium"),
    "impact_concrete": ("impact", "impactGeneric_light"),
    "impact_stone": ("impact", "impactMining"),
    "impact_wood": ("impact", "impactWood_medium"),
    "footstep": ("impact", "footstep_concrete"),
    "explosion": ("scifi", "explosionCrunch"),
    "plasma_fire": ("scifi", "laserLarge"),
    "drone_shot": ("scifi", "laserSmall"),
}


def decode(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
        check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def loudest_window_db(x):
    win = int(RATE * 0.05)
    if len(x) < win:
        x = np.pad(x, (0, win - len(x)))
    sq = np.convolve(x.astype(np.float64) ** 2, np.ones(win) / win, mode="valid")
    return 10.0 * np.log10(max(sq.max(), 1e-12))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--packs", required=True)
    ap.add_argument("--synth", required=True)
    ap.add_argument("--only", default="", help="comma-separated ids")
    args = ap.parse_args()
    only = set(filter(None, args.only.split(",")))
    os.makedirs(OUT, exist_ok=True)
    print("%-16s %4s %8s %8s %8s %8s %7s %8s" % ("id", "take", "synth", "source", "gain", "out", "len s", "bytes"))
    failed = []
    for sid, (pack, stem) in MAPPING.items():
        if only and sid not in only:
            continue
        ref_path = os.path.join(args.synth, sid + ".wav")
        if not os.path.exists(ref_path):
            sys.exit("no synth dump for %s at %s" % (sid, ref_path))
        ref = loudest_window_db(decode(ref_path))
        srcs = sorted(glob.glob(os.path.join(args.packs, pack, "Audio", stem + "_[0-9][0-9][0-9].ogg")))[:MAX_VARIANTS]
        if not srcs:
            sys.exit("no %s takes in pack %s" % (stem, pack))
        for old in glob.glob(os.path.join(OUT, sid + ".*")) + glob.glob(os.path.join(OUT, sid + "_[0-9].*")):
            if not old.endswith(".import"):
                os.remove(old)
            elif not os.path.exists(old[:-len(".import")]):
                os.remove(old)
        kept = 0
        for i, src in enumerate(srcs):
            x = decode(src)
            level = loudest_window_db(x)
            gain = max(-GAIN_CAP_DB, min(GAIN_CAP_DB, ref - level))
            dst = os.path.join(OUT, "%s_%d.ogg" % (sid, kept))
            out = level
            for _ in range(3):  # the limiter eats some of the gain; top up and re-encode
                subprocess.run(
                    ["ffmpeg", "-v", "error", "-y", "-i", src, "-af",
                     "volume=%.2fdB,alimiter=limit=%.3f:level=disabled:attack=1:release=40" % (gain, LIMIT),
                     "-ac", "1", "-ar", str(RATE), "-c:a", "libvorbis", "-q:a", "4", dst],
                    check=True)
                out = loudest_window_db(decode(dst))
                if abs(out - ref) <= 0.5 or gain >= GAIN_CAP_DB:
                    break
                gain = min(GAIN_CAP_DB, gain + (ref - out))
            ok = abs(out - ref) <= MATCH_DB
            print("%-16s %4d %8.1f %8.1f %+8.1f %8.1f %7.2f %8s" % (
                sid if i == 0 else "", i, ref, level, gain, out, len(x) / RATE,
                os.path.getsize(dst) if ok else "dropped"))
            if ok:
                kept += 1
            else:
                os.remove(dst)
        if kept < MIN_VARIANTS:
            failed.append(sid)
    if failed:
        sys.exit("fewer than %d takes within %.1f dB of the synth: %s" % (MIN_VARIANTS, MATCH_DB, ", ".join(failed)))


if __name__ == "__main__":
    main()
