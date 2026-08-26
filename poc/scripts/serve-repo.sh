#!/usr/bin/env bash
# serve-repo.sh — Start/restart the local APT repository HTTP server
#
# Uses nginx if available, falls back to python3 http.server.
#
# Usage:
#   ./scripts/serve-repo.sh [start|stop|status]

set -euo pipefail

POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="${POC_DIR}/apt-repository"
SERVE_PORT="${NANOBOT_REPO_PORT:-8080}"
PUBLISH_DIR="${HOME}/.aptly/public"
PID_FILE="${REPO_DIR}/.server.pid"

ACTION="${1:-status}"

start_server() {
  if nginx -t &>/dev/null; then
    echo "Using nginx on port ${SERVE_PORT}..."
    mkdir -p "${PUBLISH_DIR}"
    nginx -s stop 2>/dev/null || true
    sleep 1
    nginx
    echo "nginx started on port ${SERVE_PORT}"
  else
    echo "Nginx not available, using Python HTTP server..."
    # Stop existing python server
    if [[ -f "${PID_FILE}" ]]; then
      kill "$(cat "${PID_FILE}")" 2>/dev/null || true
      rm -f "${PID_FILE}"
    fi
    mkdir -p "${PUBLISH_DIR}"
    cd "${PUBLISH_DIR}"
    python3 -m http.server "${SERVE_PORT}" &>/dev/null &
    echo $! > "${PID_FILE}"
    echo "Python HTTP server started on port ${SERVE_PORT} (PID: $(cat "${PID_FILE}"))"
  fi
}

stop_server() {
  if nginx -t &>/dev/null 2>&1; then
    nginx -s stop 2>/dev/null || true
    echo "nginx stopped"
  fi
  if [[ -f "${PID_FILE}" ]]; then
    kill "$(cat "${PID_FILE}")" 2>/dev/null || true
    rm -f "${PID_FILE}"
    echo "Python HTTP server stopped"
  fi
}

status_server() {
  local running=false
  if curl -s "http://localhost:${SERVE_PORT}" &>/dev/null; then
    running=true
  fi
  if [[ "$running" == "true" ]]; then
    echo "Repository server is running on port ${SERVE_PORT}"
    echo "  URL: http://localhost:${SERVE_PORT}/"
  else
    echo "Repository server is NOT running on port ${SERVE_PORT}"
    echo "  Start it with: $0 start"
  fi
}

case "${ACTION}" in
  start)
    start_server
    ;;
  stop)
    stop_server
    ;;
  status)
    status_server
    ;;
  *)
    echo "Usage: $0 {start|stop|status}"
    exit 1
    ;;
esac
