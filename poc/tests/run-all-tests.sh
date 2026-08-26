#!/usr/bin/env bash
# run-all-tests.sh — Master test runner for Nanobot POC
#
# Executes all test scenarios in sequence and produces a results report.
#
# Usage:
#   sudo ./tests/run-all-tests.sh

set -euo pipefail

POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="${POC_DIR}/tests"
RESULTS_FILE="${TEST_DIR}/results/test-results.log"
REPORT_FILE="${TEST_DIR}/results/test-report.md"
TEST_USER="nanobot-testuser"

mkdir -p "${TEST_DIR}/results"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Log function
log() {
  echo -e "$1" | tee -a "${RESULTS_FILE}"
}

# Record test result
record_result() {
  local test_name="$1"
  local status="$2"
  local details="${3:-}"

  case "${status}" in
    PASS)
      PASSED=$((PASSED + 1))
      log "${GREEN}  ✅ PASS${NC} ${test_name}"
      ;;
    FAIL)
      FAILED=$((FAILED + 1))
      log "${RED}  ❌ FAIL${NC} ${test_name}"
      if [[ -n "${details}" ]]; then
        log "       Details: ${details}"
      fi
      ;;
    SKIP)
      SKIPPED=$((SKIPPED + 1))
      log "${YELLOW}  ⏭️  SKIP${NC} ${test_name}"
      ;;
  esac
}

# Check if running as root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Error: Test runner requires root privileges."
  echo "Run with: sudo $0"
  exit 1
fi

echo "=============================================" | tee "${RESULTS_FILE}"
echo "  Nanobot POC — Automated Test Suite"       | tee -a "${RESULTS_FILE}"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"    | tee -a "${RESULTS_FILE}"
echo "=============================================" | tee -a "${RESULTS_FILE}"
echo "" | tee -a "${RESULTS_FILE}"

TOTAL_SCENARIOS=9

# ─── Scenario A: OEM Setup ───────────────────────────────────
log "${BLUE}[Scenario A]${NC} OEM Setup — Install Nanobot 1.0 and Repository"
echo "-----------------------------------------------------------" | tee -a "${RESULTS_FILE}"

if bash "${TEST_DIR}/scenario-A-oem-setup.sh" 2>&1 | tee -a "${RESULTS_FILE}"; then
  record_result "Scenario A: OEM Setup" "PASS"
else
  record_result "Scenario A: OEM Setup" "FAIL"
fi
echo "" | tee -a "${RESULTS_FILE}"

# ─── Scenario B: Create Test User ────────────────────────────
log "${BLUE}[Scenario B]${NC} Create Consumer Test User"
echo "-----------------------------------------------------------" | tee -a "${RESULTS_FILE}"

if bash "${TEST_DIR}/scenario-B-create-user.sh" "${TEST_USER}" 2>&1 | tee -a "${RESULTS_FILE}"; then
  record_result "Scenario B: Create Test User" "PASS"
else
  record_result "Scenario B: Create Test User" "FAIL"
fi
echo "" | tee -a "${RESULTS_FILE}"

# ─── Scenario C: User Runs v1.0 ──────────────────────────────
log "${BLUE}[Scenario C]${NC} Test User Runs Nanobot 1.0"
echo "-----------------------------------------------------------" | tee -a "${RESULTS_FILE}"

if bash "${TEST_DIR}/scenario-C-user-runs-v1.sh" "${TEST_USER}" 2>&1 | tee -a "${RESULTS_FILE}"; then
  record_result "Scenario C: User Runs v1.0" "PASS"
else
  record_result "Scenario C: User Runs v1.0" "FAIL"
fi
echo "" | tee -a "${RESULTS_FILE}"

# ─── Scenario D: Publish v1.1 ────────────────────────────────
log "${BLUE}[Scenario D]${NC} Publish Nanobot 1.1.0 to Repository"
echo "-----------------------------------------------------------" | tee -a "${RESULTS_FILE}"

if bash "${TEST_DIR}/scenario-D-publish-v11.sh" 2>&1 | tee -a "${RESULTS_FILE}"; then
  record_result "Scenario D: Publish v1.1" "PASS"
else
  record_result "Scenario D: Publish v1.1" "FAIL"
fi
echo "" | tee -a "${RESULTS_FILE}"

# ─── Scenario E: Wait for Upgrade ────────────────────────────
log "${BLUE}[Scenario E]${NC} Wait for Automatic Upgrade"
echo "-----------------------------------------------------------" | tee -a "${RESULTS_FILE}"

if bash "${TEST_DIR}/scenario-E-wait-upgrade.sh" 2>&1 | tee -a "${RESULTS_FILE}"; then
  record_result "Scenario E: Wait for Upgrade" "PASS"
else
  record_result "Scenario E: Wait for Upgrade" "FAIL"
fi
echo "" | tee -a "${RESULTS_FILE}"

# ─── Scenario F: Verify No Sudo Used ─────────────────────────
log "${BLUE}[Scenario F]${NC} Verify No Sudo Used by Test User"
echo "-----------------------------------------------------------" | tee -a "${RESULTS_FILE}"

if bash "${TEST_DIR}/scenario-F-verify-no-sudo.sh" "${TEST_USER}" 2>&1 | tee -a "${RESULTS_FILE}"; then
  record_result "Scenario F: Verify No Sudo" "PASS"
else
  record_result "Scenario F: Verify No Sudo" "FAIL"
fi
echo "" | tee -a "${RESULTS_FILE}"

# ─── Scenario G: Verify v1.1 Running ─────────────────────────
log "${BLUE}[Scenario G]${NC} Verify Nanobot Shows v1.1 After Restart"
echo "-----------------------------------------------------------" | tee -a "${RESULTS_FILE}"

if bash "${TEST_DIR}/scenario-G-verify-v11.sh" "${TEST_USER}" 2>&1 | tee -a "${RESULTS_FILE}"; then
  record_result "Scenario G: Verify v1.1" "PASS"
else
  record_result "Scenario G: Verify v1.1" "FAIL"
fi
echo "" | tee -a "${RESULTS_FILE}"

# ─── Scenario H: Verify User Config Persistence ──────────────
log "${BLUE}[Scenario H]${NC} Verify User Configuration Persistence"
echo "-----------------------------------------------------------" | tee -a "${RESULTS_FILE}"

if bash "${TEST_DIR}/scenario-H-verify-persistence.sh" "${TEST_USER}" 2>&1 | tee -a "${RESULTS_FILE}"; then
  record_result "Scenario H: Verify Persistence" "PASS"
else
  record_result "Scenario H: Verify Persistence" "FAIL"
fi
echo "" | tee -a "${RESULTS_FILE}"

# ─── Scenario I: Tamper Repository Test ──────────────────────
log "${BLUE}[Scenario I]${NC} Tampered Package Rejected by APT"
echo "-----------------------------------------------------------" | tee -a "${RESULTS_FILE}"

if bash "${TEST_DIR}/scenario-I-tamper-repo.sh" 2>&1 | tee -a "${RESULTS_FILE}"; then
  record_result "Scenario I: Tamper Rejected" "PASS"
else
  record_result "Scenario I: Tamper Rejected" "FAIL"
fi
echo "" | tee -a "${RESULTS_FILE}"

# ─── Summary ─────────────────────────────────────────────────
TOTAL=$((PASSED + FAILED + SKIPPED))

echo "" | tee -a "${RESULTS_FILE}"
echo "=============================================" | tee -a "${RESULTS_FILE}"
echo "  Test Results Summary"                       | tee -a "${RESULTS_FILE}"
echo "=============================================" | tee -a "${RESULTS_FILE}"
echo "" | tee -a "${RESULTS_FILE}"
log "  Total:  ${TOTAL}"
log "  ${GREEN}Passed: ${PASSED}${NC}"
log "  ${RED}Failed: ${FAILED}${NC}"
log "  ${YELLOW}Skipped: ${SKIPPED}${NC}"
echo "" | tee -a "${RESULTS_FILE}"

if [[ ${FAILED} -eq 0 ]]; then
  log "${GREEN}=============================================${NC}"
  log "${GREEN}  ALL TESTS PASSED ✅${NC}"
  log "${GREEN}=============================================${NC}"
  EXIT_CODE=0
else
  log "${RED}=============================================${NC}"
  log "${RED}  SOME TESTS FAILED ❌${NC}"
  log "${RED}=============================================${NC}"
  EXIT_CODE=1
fi

# Generate markdown report
cat > "${REPORT_FILE}" << REPORT
# Nanobot POC — Test Report

**Date:** $(date '+%Y-%m-%d %H:%M:%S')
**Result:** $([ ${FAILED} -eq 0 ] && echo "✅ ALL PASSED" || echo "❌ ${FAILED} FAILED")

## Summary

| Metric | Count |
|--------|-------|
| Total  | ${TOTAL} |
| Passed | ${PASSED} |
| Failed | ${FAILED} |
| Skipped | ${SKIPPED} |

## Scenarios

| Scenario | Description | Status |
|----------|-------------|--------|
REPORT

# Parse results for the report
while IFS= read -r line; do
  if [[ "${line}" == *"PASS"* ]] || [[ "${line}" == *"FAIL"* ]] || [[ "${line}" == *"SKIP"* ]]; then
    echo "${line}" | tee -a "${REPORT_FILE}"
  fi
done < "${RESULTS_FILE}"

echo "" | tee -a "${RESULTS_FILE}"
log "Full log: ${RESULTS_FILE}"
log "Report:   ${REPORT_FILE}"

exit ${EXIT_CODE}
