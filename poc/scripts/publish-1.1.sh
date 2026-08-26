#!/usr/bin/env bash
# publish-1.1.sh — Build and publish Nanobot 1.1.0 to the local repo
#
# This script simulates the OEM publishing a new version.
# After running this, unattended-upgrades should automatically
# upgrade installed nanobot packages from 1.0.0 to 1.1.0.
#
# Usage:
#   ./scripts/publish-1.1.sh

set -euo pipefail

POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="${POC_DIR}/apt-repository"
GNUPG_HOME="${REPO_DIR}/gpg-home"

echo "=== Publishing Nanobot 1.1.0 to POC Repository ==="

# Verify GPG key exists
if [[ ! -d "${GNUPG_HOME}" ]]; then
  echo "ERROR: GPG key ring not found at ${GNUPG_HOME}"
  echo "Run setup-repo.sh first."
  exit 1
fi

# Get GPG key ID
GPG_KEY_ID=$(gpg --homedir "${GNUPG_HOME}" --list-keys --with-colons "nanobot-poc@localhost" \
  | grep '^fpr' | head -1 | cut -d: -f10)

if [[ -z "${GPG_KEY_ID}" ]]; then
  echo "ERROR: Could not find GPG key for nanobot-poc@localhost"
  exit 1
fi

echo "[1/3] Building nanobot 1.1.0 package..."
bash "${POC_DIR}/scripts/build-deb.sh" 1.1.0

echo "[2/3] Adding package to aptly repository..."
aptly repo add nanobot-poc "${POC_DIR}/packages/nanobot-1.1.0.deb"

echo "[3/3] Publishing repository update..."
# Publish or update the repository
if aptly publish list 2>/dev/null | grep -q "noble"; then
  aptly publish update noble filesystem:local: \
    --gpg-key="${GPG_KEY_ID}" \
    --batch --passphrase="" \
    -skip-contents=true 2>/dev/null
  echo "  Repository updated."
else
  aptly publish repo \
    --distribution=noble \
    --component=main \
    --gpg-key="${GPG_KEY_ID}" \
    --batch --passphrase="" \
    -skip-contents=true \
    nanobot-poc \
    filesystem:local:
  echo "  Repository published."
fi

echo ""
echo "=== Nanobot 1.1.0 published successfully ==="
echo "  Package: ${POC_DIR}/packages/nanobot-1.1.0.deb"
echo "  Clients will receive this update via APT."
echo ""
echo "To trigger immediate upgrade on POC clients:"
echo "  sudo systemctl start nanobot-poc-upgrade.service"
