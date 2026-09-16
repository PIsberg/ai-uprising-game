# Agent Lattice (lat.md) check runner (Windows).
# Validates wiki links, directory index, sections, and @lat code references.
param([switch]$Verbose)

Write-Host "== Validating Agent Lattice (lat.md) =="
$extraArgs = @()
if ($Verbose) { $extraArgs += "--verbose" }

if (Get-Command lat -ErrorAction SilentlyContinue) {
  & lat check @extraArgs
} else {
  & npx -y lat.md@^0.12.1 check @extraArgs
}

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
