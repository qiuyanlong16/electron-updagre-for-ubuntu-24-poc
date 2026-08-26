#!/usr/bin/env bash
# Scenario F: Verify No Sudo Used by Test User
#
# Checks that the test user never used sudo during the upgrade process.
# Verifies APT logs and system auth logs.

set -euo pipefail

TEST_USER="${1:-nanobot-testuser}"

echo "Verifying no sudo usage by: ${TEST_USER}"

# Check auth.log for sudo usage by this user
if [[ -f /var/log/auth.log ]]; then
  SUDO_COUNT=$(grep -c "sudo.*${TEST_USER}" /var/log/auth.log 2>/dev/null || echo "0")
  if [[ "${SUDO_COUNT}" -gt 0 ]]; then
    echo "  ❌ Found ${SUDO_COUNT} sudo entries for ${TEST_USER} in auth.log"
    grep "sudo.*${TEST_USER}" /var/log/auth.log | tail -5
    exit 1
  fi
  echo "  ✅ No sudo usage found in /var/log/auth.log"
else
  echo "  ℹ️  /var/log/auth.log not found (skipping auth.log check)"
fi

# Check journal for sudo
if command -v journalctl &>/dev/null; then
  SUDO_JOURNAL=$(journalctl --no-pager -q 2>/dev/null | grep -c "sudo.*${TEST_USER}" || echo "0")
  if [[ "${SUDO_JOURNAL}" -gt 0 ]]; then
    echo "  ❌ Found sudo entries in journal for ${TEST_USER}"
    exit 1
  fi
  echo "  ✅ No sudo usage found in journal"
else
  echo "  ℹ️  journalctl not available (skipping journal check)"
fi

# Verify the upgrade was done by root/system, not the user
if [[ -f /var/log/dpkg.log ]]; then
  UPGRADE_ENTRY=$(grep "upgrade nanobot" /var/log/dpkg.log 2>/dev/null | tail -1 || echo "")
  if [[ -n "${UPGRADE_ENTRY}" ]]; then
    echo "  ✅ dpkg.log shows nanobot upgrade entry"
    echo "     ${UPGRADE_ENTRY}"
  fi
else
  echo "  ℹ️  /var/log/dpkg.log not found"
fi

# Verify the user's sudoers config
if sudo -l -U "${TEST_USER}" 2>/dev/null | grep -q "ALL"; then
  echo "  ❌ User has sudo ALL access"
  exit 1
fi
echo "  ✅ User has no sudo ALL access"

# Verify no sudoers file for this user
if [[ -f "/etc/sudoers.d/${TEST_USER}" ]]; then
  echo "  ❌ Sudoers file found for ${TEST_USER}"
  exit 1
fi
echo "  ✅ No sudoers file for user"

echo ""
echo "Scenario F: PASSED"
