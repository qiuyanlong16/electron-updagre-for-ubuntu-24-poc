#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
bash "$ROOT/scripts/set-update-policy.sh" none 1.0.0
# launch the app, capture its PID, and ALWAYS clean it up on exit so this case does not leave a
# stray byclaw process behind (M-3). The screenshot is saved for manual verification, so killing
# the live window after capture is safe.
DISPLAY=:0 /opt/lenovo/byclaw/byclaw 2>/dev/null &
APP_PID=$!
cleanup() { kill "$APP_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 3; bash "$ROOT/tests-v2/screenshot.sh" "$EV/case-13-latest.png"
# read window title / DOM via... no DevTools automation; assert via screenshot + log
echo "Manually verify '当前已是最新版本' shown; screenshot saved." | tee "$EV/case-13.txt"
echo NOT-TESTED > "$EV/case-13.verdict"  # flip to PASS after visual confirm
