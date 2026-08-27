#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
echo "Normal: launch 1.0.0, note PID; ROOT: trigger upgrade to 1.1.0; assert PID alive + UI shows READY_OPTIONAL/READY_FORCE"
echo NOT-TESTED > "$EV/case-12.verdict"
