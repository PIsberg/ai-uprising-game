#!/usr/bin/env bash
# Side-by-side contact sheet of a before/after clip pair, for placing the
# changelog viewer's PR markers (the changelog-clip skill): row i is the frame
# at i*step seconds, before on the left, after on the right.
#   tools/changelog_strip.sh <before.mp4> <after.mp4> <out.png> [step=0.25]
set -euo pipefail

if [ $# -lt 3 ]; then
  sed -n '2,5p' "$0"; exit 2
fi
before=$1; after=$2; out=$3; step=${4:-0.25}
native() { if command -v cygpath >/dev/null; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$(native "$after")")
rows=$(awk "BEGIN{printf \"%d\", $dur/$step + 0.999}")
ffmpeg -v error -y -i "$(native "$before")" -i "$(native "$after")" -filter_complex \
  "[0]fps=1/$step,scale=320:-1,tile=1x$rows[a];[1]fps=1/$step,scale=320:-1,tile=1x$rows[b];[a][b]hstack" \
  -frames:v 1 "$(native "$out")"
echo "ok $out  rows=$rows  row i = i*$step s"
