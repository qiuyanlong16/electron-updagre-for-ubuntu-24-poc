#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
# publish-byclaw.sh is a NORMAL-USER aptly script (no sudo); only systemctl is root.
echo "ROOT: ensure app stopped — sudo pkill -f /opt/lenovo/byclaw || true"
echo "Normal: bash \"$ROOT/scripts/publish-byclaw.sh\" 1.1.0   # aptly publish, NO sudo"
echo "ROOT: sudo systemctl start byclaw-poc-upgrade.service"
echo "Normal: launch byclaw, read version, expect 1.1.0"
echo NOT-TESTED > "$EV/case-11.verdict"
