#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
echo "ROOT: ensure app stopped; sudo ./scripts/publish-byclaw.sh 1.1.0 (as user) ; sudo systemctl start byclaw-poc-upgrade.service"
echo "Normal: launch byclaw, read version, expect 1.1.0"
echo NOT-TESTED > "$EV/case-11.verdict"
