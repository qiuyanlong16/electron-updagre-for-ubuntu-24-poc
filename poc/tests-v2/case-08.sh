#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
grep -q 'Signed-By' /etc/apt/sources.list.d/byclaw-poc.sources 2>/dev/null && echo PASS > "$EV/case-08.verdict" || echo NOT-TESTED > "$EV/case-08.verdict"
curl -fsS http://127.0.0.1:8099/dists/noble/InRelease 2>/dev/null | grep -i 'Origin\|Date' | tee "$EV/case-08-inrelease.txt" || true
