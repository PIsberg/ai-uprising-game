#!/usr/bin/env bash
# Agent Lattice (lat.md) check runner.
# Validates wiki links, directory index, sections, and @lat code references.
set -euo pipefail

echo "== Validating Agent Lattice (lat.md) =="
if command -v lat >/dev/null 2>&1; then
  lat check "$@"
else
  npx -y lat.md@^0.12.1 check "$@"
fi
