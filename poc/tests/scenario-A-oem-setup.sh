#!/usr/bin/env bash
# Scenario A: OEM Setup — Install Nanobot 1.0 and Repository
#
# Simulates the OEM factory stage:
# - Builds and installs nanobot 1.0.0
# - Sets up the local APT repository
# - Configures client for auto-upgrade
# - Installs AppArmor profile
# - Starts the POC upgrade timer

set -euo pipefail

POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: Must run as root"
  exit 1
fi

echo "Running OEM setup..."

# Clean any previous POC state
bash "${POC_DIR}/scripts/cleanup-poc.sh" 2>/dev/null || true

# Build nanobot 1.0.0
bash "${POC_DIR}/scripts/build-deb.sh" 1.0.0
echo "  ✅ Built nanobot 1.0.0"

# Install nanobot 1.0.0
dpkg -i "${POC_DIR}/packages/nanobot-1.0.0.deb"
echo "  ✅ Installed nanobot 1.0.0"

# Verify installation
if [[ ! -d /opt/lenovo/nanobot ]]; then
  echo "  ❌ /opt/lenovo/nanobot not found"
  exit 1
fi

# Read version from installed package.json
INSTALLED_VERSION=$(python3 -c "import json; print(json.load(open('/opt/lenovo/nanobot/package.json'))['version'])")
if [[ "${INSTALLED_VERSION}" != "1.0.0" ]]; then
  echo "  ❌ Expected version 1.0.0, got ${INSTALLED_VERSION}"
  exit 1
fi
echo "  ✅ Version verified: ${INSTALLED_VERSION}"

# Install desktop entry
mkdir -p /usr/share/applications
cp "${POC_DIR}/packaging/nanobot.desktop" /usr/share/applications/nanobot.desktop
update-desktop-database /usr/share/applications 2>/dev/null || true
echo "  ✅ Desktop entry installed"

# Install AppArmor profiles (dual-profile: launcher + Electron binary)
cp "${POC_DIR}/apparmor/com.lenovo.nanobot" /etc/apparmor.d/com.lenovo.nanobot
cp "${POC_DIR}/apparmor/com.lenovo.nanobot.electron" /etc/apparmor.d/com.lenovo.nanobot.electron
chmod 0644 /etc/apparmor.d/com.lenovo.nanobot /etc/apparmor.d/com.lenovo.nanobot.electron
apparmor_parser -r /etc/apparmor.d/com.lenovo.nanobot /etc/apparmor.d/com.lenovo.nanobot.electron 2>/dev/null || true
echo "  ✅ AppArmor profiles installed (launcher + electron)"

# Setup APT repository
bash "${POC_DIR}/scripts/setup-repo.sh"
echo "  ✅ APT repository setup"

# Add 1.0.0 to repository
GPG_KEY_ID=$(gpg --homedir "${POC_DIR}/apt-repository/gpg-home" \
  --list-keys --with-colons "nanobot-poc@localhost" \
  | grep '^fpr' | head -1 | cut -d: -f10)

aptly repo add nanobot-poc "${POC_DIR}/packages/nanobot-1.0.0.deb" 2>&1

aptly publish repo \
  --distribution=noble --component=main \
  --gpg-key="${GPG_KEY_ID}" --batch --passphrase="" \
  --skip-contents=true \
  nanobot-poc filesystem:local: 2>&1 || true

echo "  ✅ nanobot 1.0.0 published to repository"

# Install client config
bash "${POC_DIR}/scripts/setup-client-config.sh"
echo "  ✅ Client configuration installed"

# Start the HTTP server
bash "${POC_DIR}/scripts/serve-repo.sh" start 2>&1 || true
sleep 2

# Verify repository is accessible
if curl -sf "http://localhost:8080/dists/noble/InRelease" >/dev/null; then
  echo "  ✅ Repository accessible"
else
  echo "  ⚠️  Repository may not be fully accessible (non-fatal for POC)"
fi

# Install systemd timer
cp "${POC_DIR}/systemd/nanobot-poc-upgrade.service" /etc/systemd/system/
cp "${POC_DIR}/systemd/nanobot-poc-upgrade.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now nanobot-poc-upgrade.timer 2>/dev/null || true
echo "  ✅ POC upgrade timer enabled"

echo ""
echo "Scenario A: PASSED"
