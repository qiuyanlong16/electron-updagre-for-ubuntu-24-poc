#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
ps -eo pid,args | grep -E 'byclaw|electron' | grep -v grep | tee "$EV/case-06-ps.txt"
# app must be running first; otherwise no-sandbox check would false-PASS on an empty process list
if ! grep -qE 'byclaw|electron' "$EV/case-06-ps.txt" 2>/dev/null; then echo NOT-TESTED > "$EV/case-06.verdict"; exit 0; fi
if grep -q -- '--no-sandbox' "$EV/case-06-ps.txt"; then echo FAIL > "$EV/case-06.verdict"; else echo PASS > "$EV/case-06.verdict"; fi
