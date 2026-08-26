#!/usr/bin/env bash
# cleanup-poc.sh — Remove all POC artifacts from the system
#
# WARNING: This removes nanobot packages, repository config,
# test users, and systemd timers.
#
# Usage:
#   sudo ./scripts/cleanup-poc.sh

set -euo pipefail

TEST_USER="nanobot-testuser"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Error: This script requires root privileges."
  echo "Run with: sudo $0"
  exit 1
fi

echo "=== Cleaning up Nanobot POC ==="
echo ""

# Stop and remove systemd units
echo "[1/7] Removing systemd units..."
systemctl stop nanobot-poc-upgrade.timer 2>/dev/null || true
systemctl stop nanobot-poc-upgrade.service 2>/dev/null || true
systemctl disable nanobot-poc-upgrade.timer 2>/dev/null || true
rm -f /etc/systemd/system/nanobot-poc-upgrade.service
rm -f /etc/systemd/system/nanobot-poc-upgrade.timer
systemctl daemon-reload 2>/dev/null || true
echo "  ✅ Systemd units removed"

# Remove nanobot package
echo "[2/7] Removing nanobot package..."
if dpkg-query -W nanobot &>/dev/null; then
  dpkg --purge nanobot 2>/dev/null || true
fi
rm -rf /opt/lenovo/nanobot
echo "  ✅ nanobot package removed"

# Remove desktop entry
echo "[3/7] Removing desktop entry..."
rm -f /usr/share/applications/nanobot.desktop
update-desktop-database /usr/share/applications 2>/dev/null || true
echo "  ✅ Desktop entry removed"

# Remove AppArmor profile
echo "[4/7] Removing AppArmor profile..."
if [[ -f /etc/apparmor.d/com.lenovo.nanobot ]]; then
  apparmor_parser -R /etc/apparmor.d/com.lenovo.nanobot 2>/dev/null || true
  rm -f /etc/apparmor.d/com.lenovo.nanobot
fi
echo "  ✅ AppArmor profile removed"

# Remove APT repository config
echo "[5/7] Removing APT repository config..."
rm -f /etc/apt/sources.list.d/nanobot-poc.sources
rm -f /etc/apt/apt.conf.d/60nanobot-poc-upgrades
rm -f /usr/share/keyrings/nanobot-poc.gpg
echo "  ✅ APT repository config removed"

# Stop repository server
echo "[6/7] Stopping repository server..."
POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
bash "${POC_DIR}/scripts/serve-repo.sh" stop 2>/dev/null || true

# Disable nginx site
rm -f /etc/nginx/sites-enabled/nanobot-poc
rm -f /etc/nginx/sites-available/nanobot-poc
nginx -s reload 2>/dev/null || true
echo "  ✅ Repository server stopped"

# Remove test user
echo "[7/7] Removing test user..."
if id "${TEST_USER}" &>/dev/null; then
  userdel -r "${TEST_USER}" 2>/dev/null || true
fi
echo "  ✅ Test user removed"

# Clean build artifacts
rm -rf "${POC_DIR}/packages"
echo "  ✅ Build artifacts removed"

echo ""
echo "=== POC Cleanup Complete ==="
echo ""
echo "Remaining (intentionally preserved):"
echo "  - ${POC_DIR}/apt-repository/gpg-home/ (test GPG key)"
echo "  - ${POC_DIR}/apt-repository/nanobot-poc-public.gpg"
echo "  - Source files in ${POC_DIR}/electron-app/"
