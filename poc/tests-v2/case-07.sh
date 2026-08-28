#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
# ROOT steps: load the profile + capture its enforce/complain MODE, then re-run this case.
# The mode evidence is a USER-PRODUCED artifact (root needed) — the script never invokes sudo
# itself (root-access mode: prepare, echo, pause for user to sudo). Mirrors case-02's pattern.
# /sys/kernel/security/apparmor/profiles lists each profile as "<name> (enforce|complain)";
# the byclaw profile is attachment-based so its name is the binary path /opt/lenovo/byclaw/byclaw.
echo "ROOT steps required. Review and run with sudo:"
echo "  sudo apparmor_parser -r /etc/apparmor.d/com.lenovo.byclaw   # load the byclaw profile"
echo "  sudo grep -F '/opt/lenovo/byclaw/byclaw' /sys/kernel/security/apparmor/profiles > $EV/case-07-mode.txt  # capture enforce/complain mode"
# -s: file must be NON-empty (absent OR empty => byclaw not loaded / step not run yet => NOT-TESTED, re-run)
if [ ! -s "$EV/case-07-mode.txt" ]; then echo NOT-TESTED > "$EV/case-07.verdict"; exit 0; fi
# minimality: profile file must exist first (missing file -> grep no-match -> false PASS without this guard)
if [ ! -f /etc/apparmor.d/com.lenovo.byclaw ]; then echo NOT-TESTED > "$EV/case-07.verdict"; exit 0; fi
# Mode per spec §13.1: the profile uses flags=(unconfined), so the loaded mode is (unconfined)
# (attached to the binary, runs unconfined to satisfy Chromium's broad file-access needs, grants
# userns). §13.8: Case 7 truthfully records the loading result. Accept (unconfined) [spec §13.1
# design] or (enforce) [a stricter valid profile]; REJECT (complain) [logs-only, not the spec
# design] and absent. NOTE: a flags=(unconfined) profile reports (unconfined), NOT (enforce) — an
# earlier revision of this check wrongly required (enforce) and would always FAIL the
# spec-mandated profile (caught during the root validation pass: captured mode was (unconfined)).
if ! grep -qE '\((unconfined|enforce)\)' "$EV/case-07-mode.txt"; then echo FAIL > "$EV/case-07.verdict"; exit 0; fi
# minimality: no dangerous capabilities in the profile file
if grep -qE 'sys_admin|sys_chroot|dac_read_search|setuid|setgid|fowner|chown' /etc/apparmor.d/com.lenovo.byclaw; then
  echo FAIL > "$EV/case-07.verdict"
else
  echo PASS > "$EV/case-07.verdict"
fi
