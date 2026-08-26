#!/usr/bin/env bash
# init-oem.sh — OEM stage initialization script
#
# This script performs all OEM-stage setup:
#   1. Builds nanobot 1.0.0 .deb
#   2. Installs nanobot 1.0.0
#   3. Sets up the local APT repository
#   4. Installs client configuration
#   5. Starts the POC upgrade timer
#
# Usage:
#   sudo ./scripts/init-oem.sh

set -euo pipefail

POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Check root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Error: This script requires root privileges."
  echo "Run with: sudo $0"
  exit 1
fi

echo "============================================="
echo "  Nanobot POC — OEM Stage Initialization"
echo "============================================="
echo ""

# --- Step 1: Build nanobot 1.0.0 ---
echo "[1/6] Building nanobot 1.0.0..."
bash "${POC_DIR}/scripts/build-deb.sh" 1.0.0
echo ""

# --- Step 2: Install nanobot 1.0.0 ---
echo "[2/6] Installing nanobot 1.0.0..."
dpkg -i "${POC_DIR}/packages/nanobot-1.0.0.deb"

# Install desktop entry
mkdir -p /usr/share/applications
cp "${POC_DIR}/packaging/nanobot.desktop" /usr/share/applications/nanobot.desktop
update-desktop-database /usr/share/applications 2>/dev/null || true
echo "  Desktop entry: /usr/share/applications/nanobot.desktop"

# Install AppArmor profiles (dual-profile: launcher + Electron binary)
cp "${POC_DIR}/apparmor/com.lenovo.nanobot" /etc/apparmor.d/com.lenovo.nanobot
cp "${POC_DIR}/apparmor/com.lenovo.nanobot.electron" /etc/apparmor.d/com.lenovo.nanobot.electron
apparmor_parser -r /etc/apparmor.d/com.lenovo.nanobot /etc/apparmor.d/com.lenovo.nanobot.electron 2>/dev/null || true
echo "  AppArmor profiles: com.lenovo.nanobot (+ .electron)"

echo ""

# --- Step 3: Setup APT repository ---
echo "[3/6] Setting up local APT repository..."
bash "${POC_DIR}/scripts/setup-repo.sh"
echo ""

# --- Step 4: Add 1.0.0 to the repository ---
echo "[4/6] Adding nanobot 1.0.0 to repository..."
GPG_KEY_ID=$(gpg --homedir "${POC_DIR}/apt-repository/gpg-home" \
  --list-keys --with-colons "nanobot-poc@localhost" \
  | grep '^fpr' | head -1 | cut -d: -f10)

aptly repo add nanobot-poc "${POC_DIR}/packages/nanobot-1.0.0.deb"

if aptly publish list 2>/dev/null | grep -q "noble"; then
  aptly publish update noble filesystem:local: \
    --gpg-key="${GPG_KEY_ID}" --batch --passphrase="" 2>/dev/null || true
else
  aptly publish repo \
    --distribution=noble --component=main \
    --gpg-key="${GPG_KEY_ID}" --batch --passphrase="" \
    nanobot-poc filesystem:local:
fi
echo "  nanobot 1.0.0 published to repository"
echo ""

# --- Step 5: Install client configuration ---
echo "[5/6] Installing client configuration..."
bash "${POC_DIR}/scripts/setup-client-config.sh"
echo ""

# --- Step 6: Start POC upgrade timer ---
echo "[6/6] Starting POC upgrade timer..."
cp "${POC_DIR}/systemd/nanobot-poc-upgrade.service" /etc/systemd/system/
cp "${POC_DIR}/systemd/nanobot-poc-upgrade.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now nanobot-poc-upgrade.timer 2>/dev/null || true
echo "  Timer enabled: nanobot-poc-upgrade.timer (every 2 minutes)"
echo ""

# --- Start the HTTP server ---
echo "Starting repository HTTP server..."
bash "${POC_DIR}/scripts/serve-repo.sh" start
echo ""

echo "============================================="
echo "  OEM Stage Complete"
echo "============================================="
echo ""
echo "Installed:"
echo "  nanobot 1.0.0       → /opt/lenovo/nanobot/"
echo "  Desktop entry       → /usr/share/applications/nanobot.desktop"
echo "  AppArmor profile    → /etc/apparmor.d/com.lenovo.nanobot"
echo "  APT repository      → http://localhost:8080/"
echo "  Upgrade timer       → nanobot-poc-upgrade.timer"
echo ""
echo "Next: Create a test user and run the tests."
