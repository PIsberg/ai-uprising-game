# Agent Lattice (lat.md) check runner (Windows).
# Validates wiki links, directory index, sections, and @lat code references.
# Uses the version pinned in package-lock.json, the same one CI runs, so a
# local pass and a CI pass mean the same thing.
param([switch]$Verbose)
$ErrorActionPreference = "Stop"

Write-Host "== Validating Agent Lattice (lat.md) =="
Push-Location (Join-Path $PSScriptRoot "..")
try {
  if (-not (Test-Path "node_modules/lat.md")) {
    Write-Host "-- installing pinned lat.md (npm ci)"
    npm ci
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  }
  $extraArgs = @()
  if ($Verbose) { $extraArgs += "--verbose" }
  & npx lat check @extraArgs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Pop-Location
}
