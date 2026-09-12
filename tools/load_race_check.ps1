# Cold-starts tests/loading_screen_deploy_probe windowed several times against an
# exported pack, alternating its two paths (cold loading-screen request / main menu
# warm-up joined by the loading screen), and fails if any start leaves the loading
# screen stuck or logs a failed preload(). It has to be an exported pack: the
# use_sub_threads race this guards needed binary scenes, compiled script tokens and
# a real GPU, so runs from source and the headless suite stayed green through it.
# One run proves little; each path hung in 4 to 7 of 12 cold starts when broken.
#
#   pwsh tools/load_race_check.ps1                  # export the pack, then 10 cold starts
#   pwsh tools/load_race_check.ps1 -Runs 20 -SkipExport   # reuse the last pack

param(
    [int]$Runs = 10,
    [switch]$SkipExport,
    [string]$Godot = $env:GODOT
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

if (-not $Godot -or -not (Test-Path $Godot)) {
    $guess = "C:\Users\$env:USERNAME\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
    if (Test-Path $guess) { $Godot = $guess }
    else { throw "Godot binary not found. Pass -Godot <path> or set `$env:GODOT." }
}

# "Load race check" is the shipped Windows preset plus tests/, exported as a .pck.
$pack = Join-Path $Root "build\race_check\race_check.pck"
if (-not $SkipExport) {
    New-Item -ItemType Directory -Force (Split-Path $pack) | Out-Null
    if (Test-Path $pack) { Remove-Item -Force $pack }
    Write-Host "Exporting the 'Load race check' pack..."
    & $Godot --headless --path $Root --export-pack "Load race check" $pack | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $pack)) { throw "Export of the 'Load race check' preset failed." }
}
if (-not (Test-Path $pack)) { throw "No pack at $pack. Run without -SkipExport." }
Write-Host ("Pack: {0} ({1:yyyy-MM-dd HH:mm})" -f $pack, (Get-Item $pack).LastWriteTime)

$logDir = Join-Path ([IO.Path]::GetTempPath()) "load_race_check"
New-Item -ItemType Directory -Force $logDir | Out-Null
$bad = 0
for ($i = 1; $i -le $Runs; $i++) {
    $out = Join-Path $logDir "run$i.out"
    $err = Join-Path $logDir "run$i.err"
    $mode = if ($i % 2 -eq 1) { "direct" } else { "menu" }
    $probeArgs = @("--main-pack", $pack, "--audio-driver", "Dummy", "res://tests/loading_screen_deploy_probe.tscn")
    if ($mode -eq "direct") { $probeArgs += @("--", "direct") }
    $p = Start-Process -FilePath $Godot -WorkingDirectory $logDir -PassThru `
        -ArgumentList $probeArgs -RedirectStandardOutput $out -RedirectStandardError $err
    if (-not $p.WaitForExit(60000)) { Stop-Process -Id $p.Id -Force }
    $pass = [bool](Select-String -Path $out -Pattern "^RESULT PASS" -Quiet)
    $preload = @(Select-String -Path $err -Pattern "Could not preload").Count
    $ok = $pass -and $preload -eq 0
    if (-not $ok) { $bad++ }
    $detail = "$((Select-String -Path $out -Pattern "^\s+(ok|FAIL) " | Select-Object -Last 1).Line)".Trim()
    Write-Host ("run {0,2} {1,-6}: {2}  preload_errors={3}  {4}" -f $i, $mode, $(if ($ok) { "PASS" } else { "FAIL" }), $preload, $detail)
}
Write-Host "$bad of $Runs cold starts failed (logs: $logDir)"
if ($bad -gt 0) { exit 1 }
