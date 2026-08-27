#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"; mkdir -p "$EV"
bash "$ROOT/scripts/build-version.sh" 1.0.0 2>&1 | tee "$EV/case-01-build-1.0.0.log"
bash "$ROOT/scripts/build-version.sh" 1.1.0 2>&1 | tee "$EV/case-01-build-1.1.0.log"
[ -f "$ROOT/packages/byclaw_1.0.0_amd64.deb" ] && [ -f "$ROOT/packages/byclaw_1.1.0_amd64.deb" ] \
  && echo PASS > "$EV/case-01.verdict" || echo FAIL > "$EV/case-01.verdict"
