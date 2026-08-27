#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
# ROOT steps: load the profile + capture its loaded/enforcing status, then re-run this case.
# aa-status evidence is a USER-PRODUCED artifact (root needed) — the script never invokes sudo itself
# (root-access mode: prepare, echo, pause for user to sudo). Mirrors case-02's echo+check pattern.
echo "ROOT steps required. Review and run with sudo:"
echo "  sudo apparmor_parser -r /etc/apparmor.d/com.lenovo.byclaw   # load the byclaw profile"
echo "  sudo aa-status | grep -i byclaw > $EV/case-07-aa-status.txt  # capture loaded-profile evidence"
# -s: file must be NON-empty (absent OR empty => byclaw not loaded / step not run yet => NOT-TESTED, re-run)
if [ ! -s "$EV/case-07-aa-status.txt" ]; then echo NOT-TESTED > "$EV/case-07.verdict"; exit 0; fi
# minimality: profile file must exist first (missing file -> grep no-match -> false PASS without this guard)
if [ ! -f /etc/apparmor.d/com.lenovo.byclaw ]; then echo NOT-TESTED > "$EV/case-07.verdict"; exit 0; fi
if grep -E 'sys_admin|sys_chroot|dac_read_search|setuid|setgid|fowner|chown' /etc/apparmor.d/com.lenovo.byclaw; then echo FAIL > "$EV/case-07.verdict"; else echo PASS > "$EV/case-07.verdict"; fi
