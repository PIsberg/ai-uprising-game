<#
    release.ps1 — build AI Uprising and publish / update it on a release target.

    Usage (from repo root):
        ./release itch              # rebuild fresh binaries, then push to itch.io
        ./release itch -SkipBuild   # skip the rebuild, re-push whatever is in build/
        pwsh tools/release.ps1 itch # same thing, explicit invocation

    One-time setup (you must do this — it needs your login, opens a browser):
        C:\Users\isber\butler\butler.exe login

    Updates are delta-patched by butler and go live immediately on an already-public
    page — no manual "publish" click needed. Re-run any time you want to ship changes.
#>
param(
    [Parameter(Position = 0)]
    [string]$Target = 'itch',                          # release target: itch
    [string]$ItchTarget = 'gotrex/ai-uprising',        # itch.io user/game
    [switch]$SkipBuild,                                 # re-push existing build/ without rebuilding
    [string]$Version,                                  # override the auto version stamp
    [string]$Butler = 'C:\Users\isber\butler\butler.exe'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

function Get-VersionStamp {
    $date = Get-Date -Format 'yyyy.MM.dd'
    try {
        $sha = (& git rev-parse --short HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and $sha) {
            $sha = $sha.Trim()
            $dirty = (& git status --porcelain 2>$null)
            return "$date-$sha" + $(if ($dirty) { '-wip' } else { '' })
        }
    } catch { }
    return $date
}
if (-not $Version) { $Version = Get-VersionStamp }

switch ($Target.ToLower()) {
    'itch' {
        if (-not (Test-Path $Butler)) {
            throw "butler not found at $Butler. Install from https://itchio.itch.io/butler or pass -Butler <path>."
        }
        $creds = Join-Path $env:APPDATA 'itch\butler_creds'
        $creds2 = Join-Path $env:USERPROFILE '.config\itch\butler_creds'
        if (-not (Test-Path $creds) -and -not (Test-Path $creds2)) {
            Write-Host ""
            Write-Host "butler is not logged in yet. Run this once, approve in the browser, then re-run release:" -ForegroundColor Yellow
            Write-Host "    $Butler login"
            throw "butler login required."
        }

        Write-Host "== AI Uprising -> itch.io ($ItchTarget)  v$Version ==" -ForegroundColor Cyan

        if (-not $SkipBuild) {
            Write-Host "-- Building fresh release binaries (Windows + Linux)..." -ForegroundColor Cyan
            & pwsh -NoProfile -File (Join-Path $root 'tools\build_release.ps1')
            if ($LASTEXITCODE -ne 0) { throw "Build failed." }
        }
        else {
            Write-Host "-- Skipping build (-SkipBuild); pushing existing build/ artifacts." -ForegroundColor Cyan
        }

        $winDir = Join-Path $root 'build\windows'
        $linDir = Join-Path $root 'build\linux'
        if (-not (Test-Path (Join-Path $winDir 'ai-uprising.exe')))    { throw "Missing Windows build (build\windows\ai-uprising.exe). Drop -SkipBuild to build it." }
        if (-not (Test-Path (Join-Path $linDir 'ai-uprising.x86_64'))) { throw "Missing Linux build (build\linux\ai-uprising.x86_64). Drop -SkipBuild to build it." }

        Write-Host "-- Pushing Windows -> ${ItchTarget}:windows" -ForegroundColor Cyan
        # --fix-permissions: butler detects the Linux/Mac executable and sets its
        # exec bit. A Windows-built payload carries no POSIX mode, so without this
        # Linux players can download a game they cannot run.
        & $Butler push $winDir "${ItchTarget}:windows" --userversion $Version --fix-permissions
        if ($LASTEXITCODE -ne 0) { throw "Windows push failed." }

        Write-Host "-- Pushing Linux   -> ${ItchTarget}:linux" -ForegroundColor Cyan
        & $Butler push $linDir "${ItchTarget}:linux" --userversion $Version --fix-permissions
        if ($LASTEXITCODE -ne 0) { throw "Linux push failed." }

        $user, $game = $ItchTarget.Split('/')
        Write-Host ""
        Write-Host "Released v$Version  ->  https://$user.itch.io/$game" -ForegroundColor Green
        Write-Host "Check builds any time:  $Butler status $ItchTarget"
    }
    default {
        throw "Unknown release target '$Target'. Supported targets: itch"
    }
}
