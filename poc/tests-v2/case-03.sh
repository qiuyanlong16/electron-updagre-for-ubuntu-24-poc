#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
TESTUSER=byclaw-testuser
echo "ROOT steps: sudo useradd -m -s /bin/bash $TESTUSER ; verify /home/$TESTUSER has NO lenovo/byclaw before first run"
if ! id $TESTUSER >/dev/null 2>&1; then echo NOT-TESTED > "$EV/case-03.verdict"; exit 0; fi
if [ -d /home/$TESTUSER/.config/lenovo/byclaw ]; then echo "FAIL: Home polluted pre-run" | tee "$EV/case-03.txt"; echo FAIL > "$EV/case-03.verdict"; exit 0; fi
[ -f /usr/share/applications/com.lenovo.byclaw.desktop ] && echo PASS > "$EV/case-03.verdict" || echo FAIL > "$EV/case-03.verdict"
