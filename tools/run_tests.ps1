# Headless probe suite (Windows) — imports the project, then runs every logic
# probe and checks it printed "RESULT PASS". Exits non-zero if any fail.
# Set $env:GODOT_BIN to the Godot executable, or pass it as the first argument.
param([string]$Godot = $env:GODOT_BIN)
if (-not $Godot) { $Godot = "godot" }

$probes = @(
  "res://tests/ai_director_probe.tscn",
  "res://tests/elite_probe.tscn",
  "res://tests/weapon_stats_probe.tscn",
  "res://tests/emp_probe.tscn",
  "res://tests/synth_probe.tscn",
  "res://tests/teach_probe.tscn",
  "res://tests/objective_probe.tscn",
  "res://tests/hazard_probe.tscn",
  "res://tests/loot_probe.tscn"
)

Write-Host "== importing project =="
& $Godot --headless --path . --import 2>$null | Out-Null

$failed = 0
foreach ($p in $probes) {
  $out = (& $Godot --headless --path . --audio-driver Dummy $p 2>$null | Out-String)
  if ($out -match "RESULT\s+PASS") {
    Write-Host "PASS  $p"
  } else {
    Write-Host "FAIL  $p"
    $failed++
  }
}

if ($failed -ne 0) {
  Write-Host "== $failed probe(s) failed =="
  exit 1
}
Write-Host "== all probes passed =="
