#!/usr/bin/env bash
# setup-client-config.sh — Install client configuration package
#
# Installs the APT repository source and unattended-upgrade config
# onto the target system.
#
# Usage:
#   sudo ./scripts/setup-client-config.sh

set -euo pipefail

POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT_DIR="${POC_DIR}/client-config/nanobot-poc-repo-config"

# Check root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Error: This script requires root privileges."
  echo "Run with: sudo $0"
  exit 1
fi

echo "=== Installing Nanobot POC Client Configuration ==="

# Install the .deb if built, otherwise install manually
PKG="${POC_DIR}/packages/nanobot-poc-repo-config_1.0.0_all.deb"

if [[ -f "${PKG}" ]]; then
  echo "Installing pre-built package: ${PKG}"
  dpkg -i "${PKG}"
else
  echo "Building and installing client config package..."

  # Create sources list directory
  mkdir -p /etc/apt/sources.list.d
  mkdir -p /etc/apt/apt.conf.d

  # Copy sources list
  cp "${CLIENT_DIR}/etc/apt/sources.list.d/nanobot-poc.sources" \
    /etc/apt/sources.list.d/nanobot-poc.sources
  echo "  Installed: /etc/apt/sources.list.d/nanobot-poc.sources"

  # Copy unattended-upgrades config
  cp "${CLIENT_DIR}/etc/apt/apt.conf.d/60nanobot-poc-upgrades" \
    /etc/apt/apt.conf.d/60nanobot-poc-upgrades
  echo "  Installed: /etc/apt/apt.conf.d/60nanobot-poc-upgrades"
fi

# Ensure the public key is in place
if [[ -f "${POC_DIR}/apt-repository/nanobot-poc-public.gpg" ]]; then
  mkdir -p /usr/share/keyrings
  cp "${POC_DIR}/apt-repository/nanobot-poc-public.gpg" \
    /usr/share/keyrings/nanobot-poc.gpg
  chmod 0644 /usr/share/keyrings/nanobot-poc.gpg
  echo "  Installed: /usr/share/keyrings/nanobot-poc.gpg"
else
  echo "WARNING: Public key not found. Run setup-repo.sh first."
fi

# Update APT cache
apt-get update -qq 2>/dev/null || true

echo ""
echo "=== Client configuration installed ==="
echo "  Repository: http://localhost:8080/"
echo "  Auto-upgrade: /etc/apt/apt.conf.d/60nanobot-poc-upgrades"
