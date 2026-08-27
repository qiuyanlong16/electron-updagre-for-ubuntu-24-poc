#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
bash "$ROOT/scripts/set-update-policy.sh optional 1.1.0"
# assert no apt/dpkg/systemctl in app process args (Electron/Vue/preload must NEVER invoke these — hard constraint)
# scoped to byclaw/electron processes to avoid false-FAIL from background apt-daily/unattended-upgrade
ps -eo args | grep -E 'byclaw|electron' | grep -v grep \
  | grep -E '\b(apt|apt-get|dpkg|dpkg-query|unattended-upgrade|systemctl)\b' > "$EV/case-14-noapt.txt" 2>/dev/null || true
if [ -s "$EV/case-14-noapt.txt" ]; then
  cat "$EV/case-14-noapt.txt"
  echo FAIL > "$EV/case-14.verdict"  # forbidden root-invoke command present in app args
else
  echo NOT-TESTED > "$EV/case-14.verdict"  # needs app running + human state check
fi
