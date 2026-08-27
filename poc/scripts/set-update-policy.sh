#!/usr/bin/env bash
set -euo pipefail
MODE="${1:?none|optional|force}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUB="$ROOT/apt-repository/aptly-db/public"
CURRENT="$(python3 -c "import json;print(json.load(open('$PUB/update-policy.json'))['latestVersion'])")"
case "$MODE" in
  none)     LATEST="$CURRENT"; MODE_VAL="optional" ;;
  optional) LATEST="${2:-1.1.0}"; MODE_VAL="optional" ;;
  force)    LATEST="${2:-1.1.0}"; MODE_VAL="force" ;;
  *) echo "usage: set-update-policy.sh {none|optional|force} [latestVersion]"; exit 1 ;;
esac
cat > "$PUB/update-policy.json" <<EOF
{
  "product": "byclaw",
  "channel": "stable",
  "latestVersion": "${LATEST}",
  "minimumSupportedVersion": "1.0.0",
  "mode": "${MODE_VAL}",
  "releaseNotes": ["Byclaw ${LATEST} (${MODE_VAL})"]
}
EOF
echo "[policy] mode=${MODE_VAL} latestVersion=${LATEST}"
