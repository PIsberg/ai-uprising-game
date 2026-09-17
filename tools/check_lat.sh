#!/usr/bin/env bash
# Agent Lattice (lat.md) check runner.
# Validates wiki links, directory index, sections, and @lat code references.
# Uses the version pinned in package-lock.json, the same one CI runs, so a
# local pass and a CI pass mean the same thing.
set -euo pipefail

echo "== Validating Agent Lattice (lat.md) =="
cd "$(dirname "$0")/.."
if [ ! -d node_modules/lat.md ]; then
  echo "-- installing pinned lat.md (npm ci)"
  npm ci
fi
npx lat check "$@"
