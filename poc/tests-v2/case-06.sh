#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
# match ONLY the byclaw app (/opt/lenovo/byclaw) — a bare 'electron' grep would match other Electron
# apps (stale nanobot, VS Code) and false-PASS on their args. app must be running first; else empty -> NOT-TESTED.
ps -eo pid,args | grep -F '/opt/lenovo/byclaw' | grep -v grep | tee "$EV/case-06-ps.txt"
if ! grep -qF '/opt/lenovo/byclaw' "$EV/case-06-ps.txt" 2>/dev/null; then echo NOT-TESTED > "$EV/case-06.verdict"; exit 0; fi
if grep -q -- '--no-sandbox' "$EV/case-06-ps.txt"; then echo FAIL > "$EV/case-06.verdict"; else echo PASS > "$EV/case-06.verdict"; fi
