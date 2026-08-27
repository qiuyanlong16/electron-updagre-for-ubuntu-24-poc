#!/usr/bin/env bash
# ROOT script: installs keyring + sources + unattended config + systemd units.
# The user reviews this, then runs:  sudo ./scripts/install-client-config.sh
# Per spec §14.9/§17.3: each step explains which system file it changes, then PAUSES for an
# explicit Enter before executing — review each, Ctrl-C to abort. No NOPASSWD, no password handling.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run as root (sudo ./scripts/install-client-config.sh)"; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$ROOT/apt-repository"
# step <explanation>: print what changes, then wait for Enter (EOF/non-interactive proceeds; Ctrl-C aborts).
step() { echo ">> $1"; read -r -p ">>   Press Enter to proceed (Ctrl-C to abort): " _ || true; }

step "Install repo public key to /usr/share/keyrings/byclaw-poc.gpg (0644)"
install -D -m 0644 "$REPO/byclaw-poc-public.gpg" /usr/share/keyrings/byclaw-poc.gpg

step "Install APT source /etc/apt/sources.list.d/byclaw-poc.sources (Signed-By keyring, NOT trusted:yes)"
install -D -m 0644 "$ROOT/client-config/byclaw-poc-repo-config/etc/apt/sources.list.d/byclaw-poc.sources" /etc/apt/sources.list.d/byclaw-poc.sources

step "Install unattended-upgrades config /etc/apt/apt.conf.d/60byclaw-poc-upgrades (Allowed-Origins {Lenovo:noble})"
install -D -m 0644 "$ROOT/client-config/byclaw-poc-repo-config/etc/apt/apt.conf.d/60byclaw-poc-upgrades" /etc/apt/apt.conf.d/60byclaw-poc-upgrades

step "Install systemd units /etc/systemd/system/byclaw-poc-upgrade.{service,timer}"
install -D -m 0644 "$ROOT/systemd/byclaw-poc-upgrade.service" /etc/systemd/system/byclaw-poc-upgrade.service
install -D -m 0644 "$ROOT/systemd/byclaw-poc-upgrade.timer" /etc/systemd/system/byclaw-poc-upgrade.timer

step "systemctl daemon-reload + enable --now byclaw-poc-upgrade.timer"
systemctl daemon-reload
systemctl enable --now byclaw-poc-upgrade.timer

step "apt-get update (pulls the signed byclaw repo index)"
apt-get update

echo "[install-client-config] done"
