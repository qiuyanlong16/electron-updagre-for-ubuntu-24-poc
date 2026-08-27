#!/usr/bin/env bash
# One-shot dependency installer (spec §19.2 deliverable #2). Normal user, no sudo.
# Installs the Byclaw electron-app npm dependencies; chain into build-version.sh to build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo ">> Installing npm dependencies for the Byclaw electron-app..."
cd "$ROOT/electron-app"
npm install --no-audit --no-fund
echo "[bootstrap] done. Build a version with:  bash scripts/build-version.sh 1.0.0"
