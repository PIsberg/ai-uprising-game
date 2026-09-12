#!/usr/bin/env bash
# Headless probe suite — imports the project, then runs every probe listed in
# tools/probes.txt and checks it printed "RESULT PASS". Exits non-zero if any
# probe fails (for CI). Override the binary with GODOT_BIN=/path/to/godot.
#
# The probe list lives in tools/probes.txt (shared with run_tests.ps1 — never
# add a probe here). Each probe runs with stdout AND stderr captured, under a
# timeout, so a probe that script-errors or hangs before printing RESULT shows
# its cause instead of a truncated list of "ok" lines (issues #74, #75, #100).
set -uo pipefail
GODOT="${GODOT_BIN:-godot}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${PROBE_MANIFEST:-$HERE/probes.txt}"   # PROBE_MANIFEST=<file> runs a subset
PROBE_TIMEOUT="${PROBE_TIMEOUT:-900}"   # seconds per probe; the slowest suite probe takes ~4 min

PROBES=()
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"
  line="${line//[[:space:]]/}"
  [ -n "$line" ] && PROBES+=("$line")
done < "$MANIFEST"

echo "== importing project =="
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

failed=0
for p in "${PROBES[@]}"; do
  if command -v timeout >/dev/null 2>&1; then
    out="$(timeout "$PROBE_TIMEOUT" "$GODOT" --headless --path . --audio-driver Dummy "$p" 2>&1)"; rc=$?
  else
    out="$("$GODOT" --headless --path . --audio-driver Dummy "$p" 2>&1)"; rc=$?
  fi
  if grep -q "RESULT PASS" <<<"$out"; then
    echo "PASS  $p"
  else
    if [ "$rc" -eq 124 ]; then
      echo "FAIL  $p  (timed out after ${PROBE_TIMEOUT}s - no RESULT line)"
    else
      echo "FAIL  $p  (exit $rc)"
    fi
    # The cause first: script errors are what a dead-before-RESULT probe hides.
    grep -E "SCRIPT ERROR|ERROR:|Parse Error" <<<"$out" | head -n 10 | sed "s/^/      /"
    echo "      --- last 20 lines ---"
    tail -n 20 <<<"$out" | sed "s/^/      /"
    failed=$((failed + 1))
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "== $failed probe(s) failed =="
  exit 1
fi
echo "== all ${#PROBES[@]} probes passed =="
