#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUB="$ROOT/apt-repository/aptly-db/public"
PIDF="$ROOT/apt-repository/.server.pid"
LOGF="$ROOT/logs/serve-repo.log"
PORT=8099
case "${1:-status}" in
  start)
    if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then echo "already running $(cat "$PIDF")"; exit 0; fi
    mkdir -p "$(dirname "$LOGF")"
    cd "$PUB"
    nohup python3 -m http.server --bind 127.0.0.1 "$PORT" > "$LOGF" 2>&1 &
    echo $! > "$PIDF"
    sleep 1
    curl -fsS "http://127.0.0.1:${PORT}/dists/noble/InRelease" >/dev/null && echo "started pid=$(cat "$PIDF")" || { echo "ERROR: InRelease unreachable"; exit 1; }
    ;;
  status)
    if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then echo "running pid=$(cat "$PIDF")"; else echo "stopped"; fi
    curl -fsS "http://127.0.0.1:${PORT}/update-policy.json" >/dev/null 2>&1 && echo "policy: ok" || echo "policy: unreachable"
    ;;
  stop)
    [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null || true; rm -f "$PIDF"; echo "stopped"
    ;;
esac
