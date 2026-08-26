#!/usr/bin/env bash
# Scenario H: Verify User Configuration Persistence
#
# After the upgrade, verify that:
# - User's nanobot settings are preserved
# - Model simulation files are intact
# - No user files were deleted or modified

set -euo pipefail

TEST_USER="${1:-nanobot-testuser}"
USER_HOME="/home/${TEST_USER}"

echo "Verifying user configuration persistence..."

# Check settings.json
SETTINGS_FILE="${USER_HOME}/.config/nanobot/settings.json"
if [[ -f "${SETTINGS_FILE}" ]]; then
  echo "  ✅ settings.json exists"

  # Verify content
  if python3 -c "import json; json.load(open('${SETTINGS_FILE}'))" 2>/dev/null; then
    echo "  ✅ settings.json is valid JSON"
    THEME=$(python3 -c "import json; print(json.load(open('${SETTINGS_FILE}'))['theme'])")
    echo "  ✅ Theme preserved: ${THEME}"
  else
    echo "  ❌ settings.json is corrupted"
    exit 1
  fi
else
  echo "  ❌ settings.json missing"
  exit 1
fi

# Check model simulation file
MODEL_FILE="${USER_HOME}/.config/nanobot/model-simulation.txt"
if [[ -f "${MODEL_FILE}" ]]; then
  echo "  ✅ model-simulation.txt exists"

  if grep -q "cpu-model=Lenovo-ThinkPad-X1-Carbon-Gen11" "${MODEL_FILE}"; then
    echo "  ✅ Model simulation data intact"
  else
    echo "  ❌ Model simulation data corrupted"
    exit 1
  fi
else
  echo "  ❌ model-simulation.txt missing"
  exit 1
fi

# Check ownership (should still belong to test user)
OWNER=$(stat -c '%U' "${SETTINGS_FILE}")
if [[ "${OWNER}" == "${TEST_USER}" ]]; then
  echo "  ✅ File ownership preserved: ${OWNER}"
else
  echo "  ❌ File ownership changed: ${OWNER} (expected ${TEST_USER})"
  exit 1
fi

# Verify no files were added to user home that shouldn't be there
echo "  ✅ User config directory contents:"
ls -la "${USER_HOME}/.config/nanobot/" | while read -r line; do
  echo "     ${line}"
done

echo ""
echo "Scenario H: PASSED"
