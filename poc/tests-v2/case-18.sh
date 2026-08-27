#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
TESTUSER=byclaw-testuser
# SHA256 before/after (spec §11.3)
sha256sum /home/$TESTUSER/.config/lenovo/byclaw/last-run.json 2>/dev/null | tee "$EV/case-18-sha-pre.txt" || true
echo "ROOT: trigger upgrade; Normal: sha256 after, must match pre"
echo "Offline: stop serve-repo; launch app; must still run"
echo NOT-TESTED > "$EV/case-18.verdict"
