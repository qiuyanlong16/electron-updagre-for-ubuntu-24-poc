#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
bash "$ROOT/scripts/set-update-policy.sh" force 1.1.0
echo "ROOT: ensure update-state.json installedVersion=1.1.0; Normal: screenshot READY_FORCE dialog"
echo NOT-TESTED > "$EV/case-16.verdict"
