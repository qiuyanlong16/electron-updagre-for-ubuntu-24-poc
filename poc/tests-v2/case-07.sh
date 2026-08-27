#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
echo "ROOT steps: sudo apparmor_parser -r /etc/apparmor.d/com.lenovo.byclaw ; sudo aa-status"
if ! command -v aa-status >/dev/null 2>&1; then echo NOT-TESTED > "$EV/case-07.verdict"; exit 0; fi
sudo -n aa-status 2>/dev/null | grep -i byclaw | tee "$EV/case-07-aa-status.txt" || { echo NOT-TESTED > "$EV/case-07.verdict"; exit 0; }
# minimality: profile file must exist first (missing file -> grep no-match -> false PASS without this guard)
if [ ! -f /etc/apparmor.d/com.lenovo.byclaw ]; then echo NOT-TESTED > "$EV/case-07.verdict"; exit 0; fi
if grep -E 'sys_admin|sys_chroot|dac_read_search|setuid|setgid|fowner|chown' /etc/apparmor.d/com.lenovo.byclaw; then echo FAIL > "$EV/case-07.verdict"; else echo PASS > "$EV/case-07.verdict"; fi
