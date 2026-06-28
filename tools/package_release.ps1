# Package AI Uprising release builds for itch.io (Windows + Linux).
# Exports the existing presets headlessly, then zips each build into dist/.
#
#   $env:GODOT_BIN = "C:\Program Files (x86)\godotengine4.7\Godot_v4.7-stable_win64_console.exe"
#   pwsh tools/package_release.ps1            # build + zip Windows and Linux
#   pwsh tools/package_release.ps1 -SkipTests # skip the probe suite gate
#
# Requires: export templates for Godot 4.7 installed (Editor > Manage Export
# Templates, or it's already set up since build/ exists).
param(
  [string]$Godot = $env:GODOT_BIN,
  [string]$Version = "1.0.0",
  [switch]$SkipTests
)
if (-not $Godot) { $Godot = "godot" }
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not $SkipTests) {
  Write-Host "== running probe suite ==" -ForegroundColor Cyan
  & "$PSScriptRoot/run_tests.ps1" -Godot $Godot
  if ($LASTEXITCODE -ne 0) { Write-Error "Tests failed — aborting release build."; exit 1 }
}

New-Item -ItemType Directory -Force -Path "build/windows","build/linux","dist" | Out-Null

Write-Host "== exporting Windows Desktop ==" -ForegroundColor Cyan
& $Godot --headless --path . --export-release "Windows Desktop" "build/windows/ai-uprising.exe"
if (-not (Test-Path "build/windows/ai-uprising.exe")) { Write-Error "Windows export produced no exe."; exit 1 }

Write-Host "== exporting Linux ==" -ForegroundColor Cyan
& $Godot --headless --path . --export-release "Linux" "build/linux/ai-uprising.x86_64"
if (-not (Test-Path "build/linux/ai-uprising.x86_64")) { Write-Error "Linux export produced no binary."; exit 1 }

# Zip each platform. itch.io accepts a zip per channel; the names below match the
# butler channels suggested in docs/ITCH_RELEASE.md.
$winZip = "dist/ai-uprising-windows-$Version.zip"
$linZip = "dist/ai-uprising-linux-$Version.zip"
Remove-Item -Force -ErrorAction SilentlyContinue $winZip,$linZip
Compress-Archive -Path "build/windows/ai-uprising.exe" -DestinationPath $winZip
Compress-Archive -Path "build/linux/ai-uprising.x86_64" -DestinationPath $linZip

Write-Host ""
Write-Host "== done ==" -ForegroundColor Green
Write-Host "  $winZip"
Write-Host "  $linZip"
Write-Host ""
Write-Host "Next: upload with butler (see docs/ITCH_RELEASE.md), e.g.:"
Write-Host "  butler push `"$winZip`" YOURNAME/ai-uprising:windows --userversion $Version"
Write-Host "  butler push `"$linZip`" YOURNAME/ai-uprising:linux --userversion $Version"
