#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
echo "ROOT steps: sudo systemctl start byclaw-poc-upgrade.service ; check dpkg.log upgrades byclaw only"
echo NOT-TESTED > "$EV/case-10.verdict"
