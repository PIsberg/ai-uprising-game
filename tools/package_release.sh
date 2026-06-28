#!/usr/bin/env bash
# Package AI Uprising release builds for itch.io (Windows + Linux).
# Exports the existing presets headlessly, then zips each build into dist/.
#   GODOT_BIN=/path/to/godot ./tools/package_release.sh [version]
# Requires Godot 4.7 export templates installed.
set -euo pipefail
GODOT="${GODOT_BIN:-godot}"
VERSION="${1:-1.0.0}"
cd "$(dirname "$0")/.."

if [ "${SKIP_TESTS:-0}" != "1" ]; then
  echo "== running probe suite =="
  GODOT_BIN="$GODOT" ./tools/run_tests.sh
fi

mkdir -p build/windows build/linux dist

echo "== exporting Windows Desktop =="
"$GODOT" --headless --path . --export-release "Windows Desktop" "build/windows/ai-uprising.exe"
[ -f build/windows/ai-uprising.exe ] || { echo "Windows export failed"; exit 1; }

echo "== exporting Linux =="
"$GODOT" --headless --path . --export-release "Linux" "build/linux/ai-uprising.x86_64"
[ -f build/linux/ai-uprising.x86_64 ] || { echo "Linux export failed"; exit 1; }
chmod +x build/linux/ai-uprising.x86_64

win_zip="dist/ai-uprising-windows-$VERSION.zip"
lin_zip="dist/ai-uprising-linux-$VERSION.zip"
rm -f "$win_zip" "$lin_zip"
( cd build/windows && zip -j "../../$win_zip" ai-uprising.exe )
( cd build/linux && zip -j "../../$lin_zip" ai-uprising.x86_64 )

echo
echo "== done =="
echo "  $win_zip"
echo "  $lin_zip"
echo
echo "Next: upload with butler (see docs/ITCH_RELEASE.md):"
echo "  butler push \"$win_zip\" YOURNAME/ai-uprising:windows --userversion $VERSION"
echo "  butler push \"$lin_zip\" YOURNAME/ai-uprising:linux --userversion $VERSION"
