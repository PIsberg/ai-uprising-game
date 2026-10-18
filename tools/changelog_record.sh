#!/usr/bin/env bash
# Films tools/changelog_clip.tscn on one commit with Godot's Movie Maker and
# encodes it for the changelog viewer (the changelog-clip skill). Run it once
# per commit with the same clip args and the two clips are frame-locked.
#   tools/changelog_record.sh <ref> <out.mp4> [clip args...]
#   tools/changelog_record.sh 9f7e317 build/changelog/weapons/clips/before_shotgun.mp4 gun=shotgun enemy=drone
# The ref is checked out once into a sibling worktree ../.wt-changelog-<sha>,
# seeded with this tree's .godot import cache and imported; later runs reuse
# it (remove it with `git worktree remove`). The clip scene is copied in from
# this tree, so an older commit films the same script. Needs a window (Movie
# Maker renders for real) and ffmpeg. Override the binary with GODOT_BIN.
set -euo pipefail

if [ $# -lt 2 ]; then
  sed -n '2,12p' "$0"; exit 2
fi
ref=$1; out=$2; shift 2
GODOT="${GODOT_BIN:-godot}"
FPS=60   # tools/changelog_clip.gd waits on game time, so any fixed rate works; the viewer steps at 60
# Godot is a native Windows binary under Git Bash: hand it C:/ paths.
native() { if command -v cygpath >/dev/null; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

repo=$(git rev-parse --show-toplevel)
sha=$(git rev-parse --short "$ref^{commit}")
wt="$(dirname "$repo")/.wt-changelog-$sha"
if [ ! -d "$wt" ]; then
  git worktree add --quiet --detach "$wt" "$sha"
  [ -d "$repo/.godot" ] && cp -r "$repo/.godot" "$wt/"
  echo "importing $sha into $wt"
  "$GODOT" --headless --path "$(native "$wt")" --import >/dev/null 2>&1 || { echo "import failed in $wt"; exit 1; }
fi
cp "$repo/tools/changelog_clip.gd" "$repo/tools/changelog_clip.tscn" "$wt/tools/"

mkdir -p "$(dirname "$out")"
out=$(realpath -m "$out")
avi="${out%.*}.avi"; log="${out%.*}.log"
"$GODOT" --path "$(native "$wt")" --write-movie "$(native "$avi")" --fixed-fps "$FPS" \
  res://tools/changelog_clip.tscn -- "$@" >"$log" 2>&1 || { echo "godot failed, see $log"; tail -20 "$log"; exit 1; }
grep -q "CLIP DONE" "$log" || { echo "clip did not finish, see $log"; tail -20 "$log"; exit 1; }
if grep -q "SCRIPT ERROR" "$log"; then
  echo "clip logged a SCRIPT ERROR on $sha (an API the clip uses may not exist there), see $log"; exit 1
fi

mark=$(sed -n 's/.*CLIP MARK frame=\([0-9]*\).*/\1/p' "$log")
ss=$(awk "BEGIN{printf \"%.4f\", $mark/$FPS}")
ffmpeg -v error -y -ss "$ss" -i "$(native "$avi")" -vf scale=1280:-2 -c:v libx264 -crf 23 -preset slow \
  -pix_fmt yuv420p -movflags +faststart -c:a aac -b:a 128k "$(native "$out")"
rm -f "$avi"
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$(native "$out")")
frames=$(awk "BEGIN{printf \"%d\", $dur*$FPS + 0.5}")
echo "ok $out  commit=$sha  $(grep -o 'shots=[0-9]*' "$log")  frames=$frames  ($(du -k "$out" | cut -f1) KB)"
