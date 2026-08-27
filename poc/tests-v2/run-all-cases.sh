#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EV="$ROOT/evidence-v2"; mkdir -p "$EV"
for i in $(seq -w 1 18); do
  echo "=== Case $i ==="
  bash "$ROOT/tests-v2/case-$i.sh" 2>&1 | tee "$EV/case-$i.log"
done
echo "=== Summary ==="
for i in $(seq -w 1 18); do
  v="$(cat "$EV/case-$i.verdict" 2>/dev/null || echo NOT-TESTED)"
  printf 'Case %s: %s\n' "$i" "$v"
done
