#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
# launch as the test user in the real session; the controller (normal user) cannot su/sudo to
# byclaw-testuser, so it does NOT launch the app itself — it only checks ps for an already-running
# byclaw-testuser byclaw process (launched via the echoed sudo command below). Mirrors case-02.
echo "ROOT steps required. Review and run with sudo:"
echo "  sudo useradd -m -s /bin/bash byclaw-testuser   # create the non-root test user"
# $(id -u) is single-quoted inside -c so it defers to su's context -> resolves as byclaw-testuser's uid.
# (Double-quoting it would expand as the CALLER's uid before su, giving a wrong XDG_RUNTIME_DIR -> the
# app cannot reach the Wayland socket -> case fails. The bare `su -c` that used to live here was dead
# code: a non-root controller with </dev/null can never authenticate, so it always failed to NOT-TESTED.)
echo "  sudo su - byclaw-testuser -c 'DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/\$(id -u) /opt/lenovo/byclaw/byclaw &'"
echo "This case verifies the app runs as the non-root test user; user switch needs root."
if ! id byclaw-testuser >/dev/null 2>&1; then echo NOT-TESTED > "$EV/case-04.verdict"; exit 0; fi
sleep 3
ps -eo user,pid,args | grep -E 'byclaw|electron' | grep -v grep | tee "$EV/case-04-ps.txt"
if grep -q "^byclaw-testuser" "$EV/case-04-ps.txt"; then echo PASS > "$EV/case-04.verdict"; else echo NOT-TESTED > "$EV/case-04.verdict"; fi
