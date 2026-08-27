#!/usr/bin/env bash
# ROOT script: installs keyring + sources + unattended config + systemd units.
# The user reviews this, then runs:  sudo ./scripts/install-client-config.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run as root (sudo ./scripts/install-client-config.sh)"; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$ROOT/apt-repository"
echo ">> Install repo public key to /usr/share/keyrings/byclaw-poc.gpg (0644)"
install -D -m 0644 "$REPO/byclaw-poc-public.gpg" /usr/share/keyrings/byclaw-poc.gpg
echo ">> Install APT source /etc/apt/sources.list.d/byclaw-poc.sources"
install -D -m 0644 "$ROOT/client-config/byclaw-poc-repo-config/etc/apt/sources.list.d/byclaw-poc.sources" /etc/apt/sources.list.d/byclaw-poc.sources
echo ">> Install unattended-upgrades config /etc/apt/apt.conf.d/60byclaw-poc-upgrades"
install -D -m 0644 "$ROOT/client-config/byclaw-poc-repo-config/etc/apt/apt.conf.d/60byclaw-poc-upgrades" /etc/apt/apt.conf.d/60byclaw-poc-upgrades
echo ">> Install + enable systemd timer"
install -D -m 0644 "$ROOT/systemd/byclaw-poc-upgrade.service" /etc/systemd/system/byclaw-poc-upgrade.service
install -D -m 0644 "$ROOT/systemd/byclaw-poc-upgrade.timer" /etc/systemd/system/byclaw-poc-upgrade.timer
systemctl daemon-reload
systemctl enable --now byclaw-poc-upgrade.timer
echo ">> apt-get update"
apt-get update
echo "[install-client-config] done"
