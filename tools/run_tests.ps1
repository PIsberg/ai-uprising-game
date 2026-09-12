# Headless probe suite (Windows) — imports the project, then runs every probe
# listed in tools/probes.txt and checks it printed "RESULT PASS". Exits
# non-zero if any fail. Set $env:GODOT_BIN to the Godot executable, or pass it
# as the first argument.
#
# The probe list lives in tools/probes.txt (shared with run_tests.sh — never
# add a probe here). Each probe runs with stdout AND stderr captured, under a
# timeout, so a probe that script-errors or hangs before printing RESULT shows
# its cause instead of nothing (issues #74, #75, #100).
param([string]$Godot = $env:GODOT_BIN, [int]$ProbeTimeout = 900, [string]$Manifest = "")
if (-not $Godot) { $Godot = "godot" }

$manifest = if ($Manifest) { $Manifest } else { Join-Path $PSScriptRoot "probes.txt" }   # -Manifest <file> runs a subset
$probes = @(Get-Content $manifest | ForEach-Object { ($_ -split '#')[0].Trim() } | Where-Object { $_ -ne "" })

Write-Host "== importing project =="
& $Godot --headless --path . --import 2>$null | Out-Null

$failed = 0
foreach ($p in $probes) {
  $log = [System.IO.Path]::GetTempFileName()
  $err = [System.IO.Path]::GetTempFileName()
  $started = Get-Date
  $proc = Start-Process -FilePath $Godot -ArgumentList @("--headless", "--path", ".", "--audio-driver", "Dummy", $p) `
    -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
  $timedOut = -not $proc.WaitForExit($ProbeTimeout * 1000)
  if ($timedOut) {
    # The console wrapper spawns the real engine as a child; kill both.
    Get-Process | Where-Object { $_.Name -like "Godot*" -and $_.StartTime -ge $started.AddSeconds(-2) } |
      ForEach-Object { try { $_.Kill() } catch {} }
    $proc.WaitForExit()
  }
  $out = ((Get-Content $log -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content $err -Raw -ErrorAction SilentlyContinue))
  Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $err -Force -ErrorAction SilentlyContinue
  if ($out -match "RESULT\s+PASS") {
    Write-Host "PASS  $p"
  } else {
    if ($timedOut) { Write-Host "FAIL  $p  (timed out after ${ProbeTimeout}s - no RESULT line)" }
    else { Write-Host "FAIL  $p  (exit $($proc.ExitCode))" }
    $lines = $out -split "`r?`n"
    $lines | Where-Object { $_ -match "SCRIPT ERROR|ERROR:|Parse Error" } | Select-Object -First 10 | ForEach-Object { Write-Host "      $_" }
    Write-Host "      --- last 20 lines ---"
    $lines | Select-Object -Last 20 | ForEach-Object { Write-Host "      $_" }
    $failed++
  }
}

if ($failed -ne 0) {
  Write-Host "== $failed probe(s) failed =="
  exit 1
}
Write-Host "== all $($probes.Count) probes passed =="
