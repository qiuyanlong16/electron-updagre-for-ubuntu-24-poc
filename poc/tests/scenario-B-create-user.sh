#!/usr/bin/env bash
# Scenario B: Create Consumer Test User
#
# Creates a regular (non-admin) user to simulate a consumer.
# This user must NOT have sudo access.

set -euo pipefail

TEST_USER="${1:-nanobot-testuser}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: Must run as root"
  exit 1
fi

echo "Creating test user: ${TEST_USER}..."

# Remove existing user if present
if id "${TEST_USER}" &>/dev/null; then
  userdel -r "${TEST_USER}" 2>/dev/null || true
fi

# Create user (no sudo, no admin)
useradd -m -s /bin/bash "${TEST_USER}"
echo "  ✅ User created: ${TEST_USER}"

# Verify user does NOT have sudo
if su - "${TEST_USER}" -c "sudo -n true" 2>/dev/null; then
  echo "  ❌ User ${TEST_USER} has sudo access — this should not happen"
  exit 1
fi
echo "  ✅ User does NOT have sudo access"

# Verify user has a home directory
if [[ ! -d "/home/${TEST_USER}" ]]; then
  echo "  ❌ Home directory not found"
  exit 1
fi
echo "  ✅ Home directory: /home/${TEST_USER}"

# Verify user can see the desktop entry
if su - "${TEST_USER}" -c "test -f /usr/share/applications/nanobot.desktop"; then
  echo "  ✅ Desktop entry visible to user"
else
  echo "  ❌ Desktop entry not visible"
  exit 1
fi

# Verify user can execute nanobot launcher
if su - "${TEST_USER}" -c "test -x /opt/lenovo/nanobot/nanobot"; then
  echo "  ✅ Nanobot launcher executable by user"
else
  echo "  ❌ Nanobot launcher not executable"
  exit 1
fi

# Create a user config file to test persistence later
mkdir -p "/home/${TEST_USER}/.config/nanobot"
cat > "/home/${TEST_USER}/.config/nanobot/settings.json" << 'SETTINGS'
{
  "theme": "dark",
  "language": "en-US",
  "lastOpened": "2024-01-15T10:30:00Z"
}
SETTINGS
cat > "/home/${TEST_USER}/.config/nanobot/model-simulation.txt" << 'MODEL'
# Model Simulation Config
cpu-model=Lenovo-ThinkPad-X1-Carbon-Gen11
serial=LNO-POC-2024-001
region=us
MODEL
chown -R "${TEST_USER}:${TEST_USER}" "/home/${TEST_USER}/.config/nanobot"
echo "  ✅ User config files created (for persistence test)"

echo ""
echo "Scenario B: PASSED"
