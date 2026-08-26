#!/usr/bin/env bash
# build-deb.sh — Build Nanobot .deb packages for POC
#
# Usage:
#   ./scripts/build-deb.sh <version>
#
# Examples:
#   ./scripts/build-deb.sh 1.0.0   # Build OEM version
#   ./scripts/build-deb.sh 1.1.0   # Build upgrade version
#
# Outputs: poc/packages/nanobot-<version>.deb

set -euo pipefail

POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 1.0.0"
  exit 1
fi

PKG_DIR="${POC_DIR}/packages"
BUILD_DIR="${PKG_DIR}/build-${VERSION}"
DEBIAN_DIR="${BUILD_DIR}/DEBIAN"
INSTALL_DIR="${BUILD_DIR}/opt/lenovo/nanobot"

# Clean previous build for this version
rm -rf "${BUILD_DIR}"
mkdir -p "${PKG_DIR}" "${DEBIAN_DIR}" "${INSTALL_DIR}"

echo "Building nanobot ${VERSION}..."

# Locate Electron binary
ELECTRON_BIN=""
if [[ -x "$HOME/.npm-global/lib/node_modules/electron/dist/electron" ]]; then
  ELECTRON_BIN="$HOME/.npm-global/lib/node_modules/electron/dist"
elif [[ -x "$(which electron 2>/dev/null)" ]]; then
  # Try to resolve electron and find its dist directory
  ELECTRON_BIN=$(node -e "console.log(require('electron'))" 2>/dev/null | xargs dirname)
fi

if [[ -z "${ELECTRON_BIN}" || ! -x "${ELECTRON_BIN}/electron" ]]; then
  # Try to find electron in node_modules of the electron-app directory
  ELECTRON_BIN="${POC_DIR}/electron-app/node_modules/electron/dist"
fi

if [[ ! -x "${ELECTRON_BIN}/electron" ]]; then
  echo "ERROR: Electron binary not found. Install electron first:"
  echo "  ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/ npx install-electron --no"
  exit 1
fi

echo "  Using Electron from: ${ELECTRON_BIN}"

# Copy electron app files INTO the electron resources/app directory
# so Electron auto-loads them (default_app.asar looks for resources/app/)
mkdir -p "${INSTALL_DIR}/electron/resources/app"
cp "${POC_DIR}/electron-app/main.js"         "${INSTALL_DIR}/electron/resources/app/"
cp "${POC_DIR}/electron-app/preload.js"       "${INSTALL_DIR}/electron/resources/app/"
cp "${POC_DIR}/electron-app/renderer.js"      "${INSTALL_DIR}/electron/resources/app/"
cp "${POC_DIR}/electron-app/index.html"       "${INSTALL_DIR}/electron/resources/app/"

# Set correct version in package.json
sed "s/\"version\": \"[^\"]*\"/\"version\": \"${VERSION}\"/" \
  "${POC_DIR}/electron-app/package.json" > "${INSTALL_DIR}/electron/resources/app/package.json"

# Bundle Electron binary into the package
echo "  Bundling Electron runtime (${ELECTRON_BIN})..."
cp -a "${ELECTRON_BIN}/." "${INSTALL_DIR}/electron/"
# Re-copy app files after bundling (to overwrite any defaults)
cp "${POC_DIR}/electron-app/main.js"         "${INSTALL_DIR}/electron/resources/app/"
cp "${POC_DIR}/electron-app/preload.js"       "${INSTALL_DIR}/electron/resources/app/"
cp "${POC_DIR}/electron-app/renderer.js"      "${INSTALL_DIR}/electron/resources/app/"
cp "${POC_DIR}/electron-app/index.html"       "${INSTALL_DIR}/electron/resources/app/"
sed "s/\"version\": \"[^\"]*\"/\"version\": \"${VERSION}\"/" \
  "${POC_DIR}/electron-app/package.json" > "${INSTALL_DIR}/electron/resources/app/package.json"
echo "  Electron runtime bundled ($(du -sh "${INSTALL_DIR}/electron/" | cut -f1))"

# Create launcher script — Electron auto-loads resources/app/
cat > "${INSTALL_DIR}/nanobot" << 'LAUNCHER'
#!/usr/bin/env bash
# Nanobot launcher — starts bundled Electron with sandbox enforced
# AppArmor profile explicitly forbids --no-sandbox
# Electron auto-loads the app from resources/app/main.js
NANOBOT_DIR="/opt/lenovo/nanobot"
exec "${NANOBOT_DIR}/electron/electron" "$@"
LAUNCHER
chmod 0755 "${INSTALL_DIR}/nanobot"

# Create symlink for version check
ln -sf electron/resources/app/package.json "${INSTALL_DIR}/package.json"

# --- DEBIAN/control ---
cat > "${DEBIAN_DIR}/control" << CONTROL
Package: nanobot
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Lenovo OEM <oem@lenovo.com>
Description: Lenovo Nanobot OEM Assistant
 An Electron-based OEM assistant application.
 Installed to /opt/lenovo/nanobot.
 Auto-upgrade via APT and unattended-upgrades.
CONTROL

# --- DEBIAN/postinst ---
cat > "${DEBIAN_DIR}/postinst" << 'POSTINST'
#!/bin/bash
set -e

NANOBOT_DIR="/opt/lenovo/nanobot"
RESOURCES_APP="${NANOBOT_DIR}/electron/resources/app"

# Ensure resources/app/ directory exists for Electron auto-loading
mkdir -p "${RESOURCES_APP}"

# Copy app files to resources/app/ if they exist at top level
for f in main.js preload.js renderer.js index.html package.json; do
  if [ -f "${NANOBOT_DIR}/${f}" ] && [ ! -L "${NANOBOT_DIR}/${f}" ]; then
    cp "${NANOBOT_DIR}/${f}" "${RESOURCES_APP}/"
  fi
done

# Fix permissions on installation
find "${NANOBOT_DIR}" -type d -exec chmod 0755 {} \;
find "${NANOBOT_DIR}" -type f -not -name "nanobot" -not -name "chrome-sandbox" -not -name "electron" -not -name "chrome_crashpad_handler" -exec chmod 0644 {} \;
chmod 0755 "${NANOBOT_DIR}/nanobot"
chmod 0755 "${NANOBOT_DIR}/electron/electron"
chmod 0755 "${NANOBOT_DIR}/electron/chrome_crashpad_handler"

# Set chrome-sandbox setuid root
if [ -f "${NANOBOT_DIR}/electron/chrome-sandbox" ]; then
  chown root:root "${NANOBOT_DIR}/electron/chrome-sandbox"
  chmod 4755 "${NANOBOT_DIR}/electron/chrome-sandbox"
fi

# Install AppArmor profile if present
if [ -f /etc/apparmor.d/com.lenovo.nanobot ]; then
  apparmor_parser -r /etc/apparmor.d/com.lenovo.nanobot 2>/dev/null || true
fi

# Register desktop entry
update-desktop-database /usr/share/applications 2>/dev/null || true

# Enable POC upgrade timer (if installed)
if systemctl list-unit-files nanobot-poc-upgrade.timer >/dev/null 2>&1; then
  systemctl enable --now nanobot-poc-upgrade.timer 2>/dev/null || true
fi

# Log installation
logger -t nanobot "Nanobot ${VERSION} installed successfully"

exit 0
POSTINST
chmod 0755 "${DEBIAN_DIR}/postinst"

# --- DEBIAN/prerm ---
cat > "${DEBIAN_DIR}/prerm" << 'PRERM'
#!/bin/bash
set -e

# Remove desktop entry cache
update-desktop-database /usr/share/applications 2>/dev/null || true

# Log removal
logger -t nanobot "Nanobot prerm executed"

exit 0
PRERM
chmod 0755 "${DEBIAN_DIR}/prerm"

# Build .deb with proper permissions
# Directories: 755 (rwxr-xr-x)
# DEBIAN scripts: 0755
# Regular files: 644 (rw-r--r--)
# Executables: 755 (rwxr-xr-x)
# Launcher: 755

# Fix directory permissions
find "${BUILD_DIR}" -type d -exec chmod 0755 {} \;

# Fix DEBIAN maintainer scripts permissions (must be executable)
find "${DEBIAN_DIR}" -type f -exec chmod 0755 {} \;

# Fix regular file permissions (excluding DEBIAN dir and executables)
find "${BUILD_DIR}" -type f \
  -not -path "${DEBIAN_DIR}/*" \
  -not -name "nanobot" \
  -not -name "chrome-sandbox" \
  -not -name "electron" \
  -not -name "chrome_crashpad_handler" \
  -exec chmod 0644 {} \;

# Fix executable permissions
chmod 0755 "${INSTALL_DIR}/nanobot"
chmod 0755 "${INSTALL_DIR}/electron/electron"
chmod 0755 "${INSTALL_DIR}/electron/chrome_crashpad_handler"

# Set chrome-sandbox setuid root
if [ -f "${INSTALL_DIR}/electron/chrome-sandbox" ]; then
  chmod 4755 "${INSTALL_DIR}/electron/chrome-sandbox"
fi

# dpkg-deb with root ownership
dpkg-deb --build --root-owner-group "${BUILD_DIR}" "${PKG_DIR}/nanobot-${VERSION}.deb"

echo "Built: ${PKG_DIR}/nanobot-${VERSION}.deb"
echo "  Size: $(du -h "${PKG_DIR}/nanobot-${VERSION}.deb" | cut -f1)"
echo "  Version: ${VERSION}"
