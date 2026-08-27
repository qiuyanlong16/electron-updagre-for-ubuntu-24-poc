#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
echo "ROOT steps: append TAMPER to InRelease, then sudo apt-get update (expect NO_PUBKEY/badhash Fail)"
echo "  echo TAMPER | sudo tee -a $ROOT/apt-repository/aptly-db/public/dists/noble/InRelease"
echo "  sudo apt-get update   # expect hash/signature failure"
echo NOT-TESTED > "$EV/case-09.verdict"  # set PASS/FAIL after user runs + captures apt error
