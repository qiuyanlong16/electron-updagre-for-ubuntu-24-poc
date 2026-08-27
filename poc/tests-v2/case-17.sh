#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
echo "Normal: click 立即重启; assert new process shows 1.1.0; second launch refused by single-instance lock"
echo NOT-TESTED > "$EV/case-17.verdict"
