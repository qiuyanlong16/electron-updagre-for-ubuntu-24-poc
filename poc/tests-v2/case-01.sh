#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"; mkdir -p "$EV"
# Remove any stale DEBs first so a FAILED rebuild cannot leave a prior artifact that falsely
# satisfies a file-existence check (false PASS). PASS is gated on the build EXIT STATUS, not on
# whether the .deb happens to exist after the run. (pipefail is set, so the pipeline's status
# reflects build-version.sh's exit, not tee's.) Both builds are attempted so the log shows both.
rm -f "$ROOT/packages/byclaw_1.0.0_amd64.deb" "$ROOT/packages/byclaw_1.1.0_amd64.deb"
ok=0
bash "$ROOT/scripts/build-version.sh" 1.0.0 2>&1 | tee "$EV/case-01-build-1.0.0.log" || ok=1
bash "$ROOT/scripts/build-version.sh" 1.1.0 2>&1 | tee "$EV/case-01-build-1.1.0.log" || ok=1
if [ "$ok" -eq 0 ] && [ -s "$ROOT/packages/byclaw_1.0.0_amd64.deb" ] && [ -s "$ROOT/packages/byclaw_1.1.0_amd64.deb" ]; then
  echo PASS > "$EV/case-01.verdict"
else
  echo FAIL > "$EV/case-01.verdict"
fi
