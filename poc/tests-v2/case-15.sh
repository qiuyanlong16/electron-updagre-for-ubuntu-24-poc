#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
bash "$ROOT/scripts/set-update-policy.sh optional 1.1.0"
echo "ROOT: write /var/lib/lenovo/byclaw/update-state.json installedVersion=1.1.0 (run the provided snippet)"
echo NOT-TESTED > "$EV/case-15.verdict"
