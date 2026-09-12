#!/usr/bin/env bash
# Headless probe suite — imports the project, then runs every logic probe and
# checks it printed "RESULT PASS". Exits non-zero if any probe fails (for CI).
# Override the binary with GODOT_BIN=/path/to/godot.
set -uo pipefail
GODOT="${GODOT_BIN:-godot}"

# Logic/integration probes that run fully headless (no GPU). Render probes
# (enemy_view, map) need a window and are intentionally excluded here.
PROBES=(
  res://tests/ai_director_probe.tscn
  res://tests/elite_probe.tscn
  res://tests/weapon_stats_probe.tscn
  res://tests/emp_probe.tscn
  res://tests/synth_probe.tscn
  res://tests/codex_count_probe.tscn
  res://tests/teach_probe.tscn
  res://tests/objective_probe.tscn
  res://tests/hazard_probe.tscn
  res://tests/loot_probe.tscn
  res://tests/shark_breach_probe.tscn
  res://tests/tesla_beam_probe.tscn
  res://tests/god_cheat_probe.tscn
  res://tests/enemy_combat_probe.tscn
  res://tests/projectile_fx_probe.tscn
  res://tests/warbot_face_probe.tscn
  res://tests/mission_arc_probe.tscn
  res://tests/survival_probe.tscn
  res://tests/voice_probe.tscn
  res://tests/gun_range_probe.tscn
  res://tests/titan_blink_probe.tscn
  res://tests/mauler_overload_probe.tscn
  res://tests/blast_direction_probe.tscn
  res://tests/damage_source_probe.tscn
  res://tests/seeker_grace_probe.tscn
  res://tests/victory_probe.tscn
  res://tests/convoy_probe.tscn
  res://tests/layout_check.tscn
  res://tests/screen_shock_probe.tscn
  res://tests/threaded_load_probe.tscn
)

echo "== importing project =="
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

failed=0
for p in "${PROBES[@]}"; do
  out="$("$GODOT" --headless --path . --audio-driver Dummy "$p" 2>/dev/null || true)"
  if grep -q "RESULT PASS" <<<"$out"; then
    echo "PASS  $p"
  else
    echo "FAIL  $p"
    echo "$out" | tail -n 15
    failed=$((failed + 1))
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "== $failed probe(s) failed =="
  exit 1
fi
echo "== all probes passed =="
