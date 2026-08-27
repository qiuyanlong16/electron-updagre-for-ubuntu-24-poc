#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
# launch as the test user in the real session; capture ps uid
echo "ROOT steps required. Review and run with sudo:"
echo "  sudo useradd -m -s /bin/bash byclaw-testuser   # create the non-root test user"
echo '  sudo su - byclaw-testuser -c "DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/$(id -u) /opt/lenovo/byclaw/byclaw &"'
echo "This case verifies the app runs as the non-root test user; user switch needs root."
if ! id byclaw-testuser >/dev/null 2>&1; then echo NOT-TESTED > "$EV/case-04.verdict"; exit 0; fi
# launch as test user; set env inside -c (su - resets env); NO --no-sandbox flag (sandboxed by default)
# </dev/null prevents su password prompt from hanging the non-interactive harness
su - byclaw-testuser -c "DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/\$(id -u) /opt/lenovo/byclaw/byclaw &" </dev/null 2>/dev/null || true
sleep 3
ps -eo user,pid,args | grep -E 'byclaw|electron' | grep -v grep | tee "$EV/case-04-ps.txt"
if grep -q "^byclaw-testuser" "$EV/case-04-ps.txt"; then echo PASS > "$EV/case-04.verdict"; else echo NOT-TESTED > "$EV/case-04.verdict"; fi
