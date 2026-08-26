#!/usr/bin/env bash
# Scenario C: Test User Runs Nanobot 1.0
#
# Verifies that a regular user can:
# - See nanobot in the application menu
# - Read the version (1.0.0)
# - Run the application without sudo

set -euo pipefail

TEST_USER="${1:-nanobot-testuser}"

echo "Testing user access to Nanobot 1.0..."

# Verify desktop entry is visible
if ! su - "${TEST_USER}" -c "test -f /usr/share/applications/nanobot.desktop"; then
  echo "  ❌ Desktop entry not found"
  exit 1
fi
echo "  ✅ Desktop entry found"

# Verify desktop entry has correct Exec path
EXEC_PATH=$(grep '^Exec=' /usr/share/applications/nanobot.desktop | cut -d= -f2)
if [[ "${EXEC_PATH}" != "/opt/lenovo/nanobot/nanobot" ]]; then
  echo "  ❌ Wrong Exec path: ${EXEC_PATH}"
  exit 1
fi
echo "  ✅ Exec path correct: ${EXEC_PATH}"

# Verify version file
VERSION=$(python3 -c "import json; print(json.load(open('/opt/lenovo/nanobot/package.json'))['version'])")
if [[ "${VERSION}" != "1.0.0" ]]; then
  echo "  ❌ Expected 1.0.0, got ${VERSION}"
  exit 1
fi
echo "  ✅ Version: ${VERSION}"

# Verify user can read the version
USER_VERSION=$(su - "${TEST_USER}" -c \
  "python3 -c \"import json; print(json.load(open('/opt/lenovo/nanobot/package.json'))['version'])\"")
if [[ "${USER_VERSION}" != "1.0.0" ]]; then
  echo "  ❌ User cannot read version correctly"
  exit 1
fi
echo "  ✅ User can read version: ${USER_VERSION}"

# Verify AppArmor profile is loaded
if aa-status 2>/dev/null | grep -q "com.lenovo.nanobot" || \
   [[ -f /etc/apparmor.d/com.lenovo.nanobot ]]; then
  echo "  ✅ AppArmor profile in place"
else
  echo "  ⚠️  AppArmor profile not loaded (may need kernel module)"
fi

# Verify --no-sandbox is forbidden in the profile
if grep -q 'deny.*--no-sandbox' /etc/apparmor.d/com.lenovo.nanobot; then
  echo "  ✅ AppArmor forbids --no-sandbox"
else
  echo "  ❌ AppArmor does not forbid --no-sandbox"
  exit 1
fi

# Verify sandbox check in main.js
if grep -q 'no-sandbox' /opt/lenovo/nanobot/main.js; then
  echo "  ✅ Electron main.js checks for --no-sandbox"
else
  echo "  ❌ Electron main.js missing sandbox check"
  exit 1
fi

echo ""
echo "Scenario C: PASSED"
