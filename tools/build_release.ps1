# Builds AI Uprising release binaries for Windows + Linux from the command line.
#
#   pwsh tools/build_release.ps1
#   pwsh tools/build_release.ps1 -Godot "C:\path\to\Godot_console.exe"
#
# Requirements:
#   - Godot 4.7 console editor binary (set $Godot or the GODOT env var).
#   - Matching export templates installed (4.7.stable). If missing, run with
#     -InstallTemplates to download + install them automatically.
#
# Output: build/windows/ai-uprising.exe  and  build/linux/ai-uprising.x86_64
#         (both have the game data embedded — single-file, no .pck alongside).

param(
    [string]$Godot = $env:GODOT,
    [switch]$InstallTemplates
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot   # repo root (tools/..)
Set-Location $Root

if (-not $Godot -or -not (Test-Path $Godot)) {
    # Best-effort default to the binary used during development.
    $guess = "C:\Users\$env:USERNAME\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe"
    if (Test-Path $guess) { $Godot = $guess }
    else { throw "Godot binary not found. Pass -Godot <path> or set `$env:GODOT." }
}
Write-Host "Godot: $Godot"

if ($InstallTemplates) {
    $tpz = Join-Path $env:TEMP "godot47_templates.tpz"
    $dest = Join-Path $env:APPDATA "Godot\export_templates\4.7.stable"
    Write-Host "Downloading 4.7 export templates (~1.3 GB)..."
    Invoke-WebRequest "https://github.com/godotengine/godot/releases/download/4.7-stable/Godot_v4.7-stable_export_templates.tpz" -OutFile $tpz
    $tmp = Join-Path $env:TEMP "godot47_tpz"
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    Expand-Archive -Path $tpz -DestinationPath $tmp -Force
    New-Item -ItemType Directory -Force $dest | Out-Null
    Copy-Item -Force (Join-Path $tmp "templates\*") $dest
    Write-Host "Templates installed to $dest"
}

# Generate .import metadata for any new assets before exporting.
Write-Host "Importing resources..."
& $Godot --headless --path . --import 2>$null | Out-Null

New-Item -ItemType Directory -Force "build\windows" | Out-Null
New-Item -ItemType Directory -Force "build\linux" | Out-Null

Write-Host "Exporting Windows Desktop..."
& $Godot --headless --path . --export-release "Windows Desktop" "build\windows\ai-uprising.exe"
if (-not (Test-Path "build\windows\ai-uprising.exe")) { throw "Windows export failed." }

Write-Host "Exporting Linux..."
& $Godot --headless --path . --export-release "Linux" "build\linux\ai-uprising.x86_64"
if (-not (Test-Path "build\linux\ai-uprising.x86_64")) { throw "Linux export failed." }

Write-Host ""
Write-Host "Done:"
Get-ChildItem "build\windows\ai-uprising.exe", "build\linux\ai-uprising.x86_64" |
    ForEach-Object { "  {0}  ({1:N0} MB)" -f $_.FullName, ($_.Length / 1MB) }
