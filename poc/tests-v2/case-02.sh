#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
echo "ROOT steps required. Review and run with sudo:"; echo "  sudo dpkg -i $ROOT/packages/byclaw_1.0.0_amd64.deb"
echo "Then this case checks perms as normal user."
if [ ! -d /opt/lenovo/byclaw ]; then echo NOT-TESTED > "$EV/case-02.verdict"; exit 0; fi
stat -c '%U:%G %a' /opt/lenovo/byclaw | tee "$EV/case-02-stat.txt"
if ( echo x > /opt/lenovo/byclaw/.write-test 2>/dev/null ); then echo FAIL > "$EV/case-02.verdict"; rm -f /opt/lenovo/byclaw/.write-test; else echo PASS > "$EV/case-02.verdict"; fi
