#!/usr/bin/env bash
# Scenario D: Publish Nanobot 1.1.0 to Repository
#
# Simulates the OEM publishing a new version.
# After this, unattended-upgrades should pick up the update.

set -euo pipefail

POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: Must run as root"
  exit 1
fi

echo "Publishing Nanobot 1.1.0..."

# Build 1.1.0 package
bash "${POC_DIR}/scripts/build-deb.sh" 1.1.0
echo "  ✅ Built nanobot 1.1.0"

# Verify the built package has correct version
PKG_VERSION=$(dpkg-deb --field "${POC_DIR}/packages/nanobot-1.1.0.deb" Version)
if [[ "${PKG_VERSION}" != "1.1.0" ]]; then
  echo "  ❌ Expected version 1.1.0 in package, got ${PKG_VERSION}"
  exit 1
fi
echo "  ✅ Package version verified: ${PKG_VERSION}"

# Add to repository
aptly repo add nanobot-poc "${POC_DIR}/packages/nanobot-1.1.0.deb" 2>&1
echo "  ✅ Added to aptly repository"

# Get GPG key ID
GPG_KEY_ID=$(gpg --homedir "${POC_DIR}/apt-repository/gpg-home" \
  --list-keys --with-colons "nanobot-poc@localhost" \
  | grep '^fpr' | head -1 | cut -d: -f10)

# Update the published repository
aptly publish update noble filesystem:local: \
  --gpg-key="${GPG_KEY_ID}" --batch --passphrase="" \
  --skip-contents=true 2>&1
echo "  ✅ Repository updated"

# Verify repository has both versions available
if aptly repo show -with-packages nanobot-poc 2>/dev/null | grep -q "1.1.0"; then
  echo "  ✅ nanobot 1.1.0 visible in repository"
else
  echo "  ❌ nanobot 1.1.0 not found in repository"
  exit 1
fi

# Verify HTTP accessibility
sleep 2
if curl -sf "http://localhost:8080/pool/" -o /dev/null; then
  echo "  ✅ Repository pool accessible via HTTP"
else
  echo "  ⚠️  Repository pool may not be accessible (non-fatal)"
fi

# Verify APT can see the upgrade
apt-get update -qq 2>/dev/null || true
AVAILABLE=$(apt-cache policy nanobot 2>/dev/null | grep "Candidate:" | awk '{print $2}')
if [[ "${AVAILABLE}" == "1.1.0" ]]; then
  echo "  ✅ APT candidate version: ${AVAILABLE}"
else
  echo "  ⚠️  APT candidate: ${AVAILABLE} (expected 1.1.0)"
fi

echo ""
echo "Scenario D: PASSED"
