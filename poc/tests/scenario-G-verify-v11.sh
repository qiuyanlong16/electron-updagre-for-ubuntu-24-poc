#!/usr/bin/env bash
# Scenario G: Verify Nanobot Shows v1.1 After Restart
#
# Confirms that after the upgrade, restarting nanobot shows version 1.1.0.

set -euo pipefail

TEST_USER="${1:-nanobot-testuser}"

echo "Verifying nanobot shows v1.1.0..."

# Check installed version via dpkg
PKG_VERSION=$(dpkg-query -W -f='${Version}' nanobot 2>/dev/null || echo "not-installed")
if [[ "${PKG_VERSION}" != "1.1.0" ]]; then
  echo "  ❌ Installed package version: ${PKG_VERSION} (expected 1.1.0)"
  exit 1
fi
echo "  ✅ dpkg version: ${PKG_VERSION}"

# Check version from the installed files
INSTALLED_VERSION=$(python3 -c "import json; print(json.load(open('/opt/lenovo/nanobot/package.json'))['version'])")
if [[ "${INSTALLED_VERSION}" != "1.1.0" ]]; then
  echo "  ❌ Installed files version: ${INSTALLED_VERSION} (expected 1.1.0)"
  exit 1
fi
echo "  ✅ Installed files version: ${INSTALLED_VERSION}"

# Verify user can read the new version
USER_VERSION=$(su - "${TEST_USER}" -c \
  "python3 -c \"import json; print(json.load(open('/opt/lenovo/nanobot/package.json'))['version'])\"")
if [[ "${USER_VERSION}" != "1.1.0" ]]; then
  echo "  ❌ User sees version: ${USER_VERSION} (expected 1.1.0)"
  exit 1
fi
echo "  ✅ User sees version: ${USER_VERSION}"

# Verify the desktop entry still works
if su - "${TEST_USER}" -c "test -f /usr/share/applications/nanobot.desktop"; then
  echo "  ✅ Desktop entry still present"
else
  echo "  ❌ Desktop entry missing"
  exit 1
fi

# Verify the AppArmor profile is still in place
if [[ -f /etc/apparmor.d/com.lenovo.nanobot ]]; then
  echo "  ✅ AppArmor profile still present"
else
  echo "  ❌ AppArmor profile missing"
  exit 1
fi

echo ""
echo "Scenario G: PASSED"
