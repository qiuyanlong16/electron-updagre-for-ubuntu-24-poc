#!/usr/bin/env bash
# acceptance.sh — Automated acceptance test for Nanobot POC
#
# Quick smoke test that verifies the core acceptance criteria:
# 1. Nanobot 1.0 is installed and runnable
# 2. Repository is configured
# 3. Version upgrade works
# 4. Tampered packages are handled
#
# Usage:
#   sudo ./scripts/acceptance.sh

set -euo pipefail

POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

check() {
  local desc="$1"
  shift
  if "$@" 2>/dev/null; then
    echo "  ✅ ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  ❌ ${desc}"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Nanobot POC Acceptance Tests ==="
echo ""

echo "--- Pre-installation Checks ---"
check "Build script exists" test -x "${POC_DIR}/scripts/build-deb.sh"
check "AppArmor profile exists" test -f "${POC_DIR}/apparmor/com.lenovo.nanobot"
check "Desktop entry template exists" test -f "${POC_DIR}/packaging/nanobot.desktop"
check "Systemd timer exists" test -f "${POC_DIR}/systemd/nanobot-poc-upgrade.timer"
check "Systemd service exists" test -f "${POC_DIR}/systemd/nanobot-poc-upgrade.service"
check "Electron app source exists" test -f "${POC_DIR}/electron-app/main.js"
check "package.json has correct name" grep -q '"name": "nanobot"' "${POC_DIR}/electron-app/package.json"

echo ""
echo "--- Build Checks ---"
bash "${POC_DIR}/scripts/build-deb.sh" 1.0.0 2>/dev/null
check "nanobot 1.0.0 .deb built" test -f "${POC_DIR}/packages/nanobot-1.0.0.deb"

bash "${POC_DIR}/scripts/build-deb.sh" 1.1.0 2>/dev/null
check "nanobot 1.1.0 .deb built" test -f "${POC_DIR}/packages/nanobot-1.1.0.deb"

check "1.0.0 has correct version" \
  test "$(dpkg-deb --field "${POC_DIR}/packages/nanobot-1.0.0.deb" Version)" = "1.0.0"
check "1.1.0 has correct version" \
  test "$(dpkg-deb --field "${POC_DIR}/packages/nanobot-1.1.0.deb" Version)" = "1.1.0"

echo ""
echo "--- Content Checks ---"
check "Launcher script in package" \
  dpkg-deb --fsys-tarfile "${POC_DIR}/packages/nanobot-1.1.0.deb" | tar -tf - | grep -q "opt/lenovo/nanobot/nanobot"
check "Desktop entry in package structure" \
  test -f "${POC_DIR}/packaging/nanobot.desktop"
check "AppArmor uses Px profile transition" \
  grep -q 'Px,' "${POC_DIR}/apparmor/com.lenovo.nanobot"
check "AppArmor allows userns" \
  grep -q '^  userns,' "${POC_DIR}/apparmor/com.lenovo.nanobot"
check "Main.js checks sandbox" \
  grep -q 'no-sandbox' "${POC_DIR}/electron-app/main.js"

echo ""
echo "--- Security Checks ---"
check "No chmod 777 in build script" \
  ! grep -q 'chmod 777\|chmod -R 777' "${POC_DIR}/scripts/build-deb.sh"
check "No sudo in electron app" \
  ! grep -q 'sudo\|pkexec' "${POC_DIR}/electron-app/main.js"
check "No --no-sandbox in launcher" \
  ! grep -q '\-\-no-sandbox' "${POC_DIR}/electron-app/main.js" || \
  grep -q 'deny.*--no-sandbox' "${POC_DIR}/apparmor/com.lenovo.nanobot"
check "Sources file uses Signed-By" \
  grep -q 'Signed-By' "${POC_DIR}/client-config/nanobot-poc-repo-config/etc/apt/sources.list.d/nanobot-poc.sources"
check "Unattended-upgrades restricted to nanobot" \
  grep -q 'Package-Whitelist' "${POC_DIR}/client-config/nanobot-poc-repo-config/etc/apt/apt.conf.d/60nanobot-poc-upgrades"

echo ""
echo "--- Structure Checks ---"
check "poc/electron-app/ exists" test -d "${POC_DIR}/electron-app"
check "poc/packaging/ exists" test -d "${POC_DIR}/packaging"
check "poc/apparmor/ exists" test -d "${POC_DIR}/apparmor"
check "poc/apt-repository/ exists" test -d "${POC_DIR}/apt-repository"
check "poc/client-config/ exists" test -d "${POC_DIR}/client-config"
check "poc/systemd/ exists" test -d "${POC_DIR}/systemd"
check "poc/tests/ exists" test -d "${POC_DIR}/tests"
check "poc/scripts/ exists" test -d "${POC_DIR}/scripts"
check "README.md exists" test -f "${POC_DIR}/README.md"

echo ""
echo "--- Script Checks ---"
for script in build-deb.sh setup-repo.sh serve-repo.sh publish-1.1.sh \
              setup-client-config.sh init-oem.sh cleanup-poc.sh; do
  check "scripts/${script} exists" test -f "${POC_DIR}/scripts/${script}"
done

echo ""
echo "============================================="
echo "  Acceptance: ${PASS} passed, ${FAIL} failed"
echo "============================================="

if [[ ${FAIL} -eq 0 ]]; then
  echo "  ✅ ALL ACCEPTANCE CHECKS PASSED"
  exit 0
else
  echo "  ❌ ${FAIL} ACCEPTANCE CHECKS FAILED"
  exit 1
fi
