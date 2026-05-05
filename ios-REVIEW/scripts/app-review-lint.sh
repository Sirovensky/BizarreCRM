#!/usr/bin/env bash
# app-review-lint.sh — Pre-submission App Review lint for BizarreCRM iOS
#
# Checks:
#   1. Info.plist has all required purpose strings
#   2. No private API references in source files
#   3. No debug-only print statements outside #if DEBUG guards
#   4. No hardcoded credentials in source files
#
# Exit 0 = all checks pass
# Exit 1 = one or more checks failed
#
# Bash 3.x compatible (macOS system bash).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# Exclude SPM build artifact caches (.build/checkouts/) from all source scans
SOURCES_DIR="${IOS_DIR}/Packages"
SOURCES_EXCLUDE="\.build"
INFO_PLIST="${IOS_DIR}/App/Resources/Info.plist"
REPORT_FILE="/tmp/app-review-lint-report.txt"

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
RST='\033[0m'

FAIL_COUNT=0
WARN_COUNT=0

# Helper: print a PASS line
pass() {
    printf "${GRN}[PASS]${RST} %s\n" "$1" | tee -a "${REPORT_FILE}"
}

# Helper: print a FAIL line and increment counter
fail() {
    printf "${RED}[FAIL]${RST} %s\n" "$1" | tee -a "${REPORT_FILE}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

# Helper: print a WARN line
warn() {
    printf "${YLW}[WARN]${RST} %s\n" "$1" | tee -a "${REPORT_FILE}"
    WARN_COUNT=$((WARN_COUNT + 1))
}

# Helper: section header
section() {
    echo "" | tee -a "${REPORT_FILE}"
    echo "=== $1 ===" | tee -a "${REPORT_FILE}"
}

# -----------------------------------------------------------------------
# Init report
# -----------------------------------------------------------------------
echo "" > "${REPORT_FILE}"
echo "BizarreCRM iOS — App Review Lint Report" | tee -a "${REPORT_FILE}"
echo "Date: $(date)" | tee -a "${REPORT_FILE}"
echo "IOS_DIR: ${IOS_DIR}" | tee -a "${REPORT_FILE}"

# -----------------------------------------------------------------------
# 1. Info.plist purpose strings
# -----------------------------------------------------------------------
section "1. Info.plist required purpose strings"

if [ ! -f "${INFO_PLIST}" ]; then
    fail "Info.plist not found at ${INFO_PLIST} — run 'bash ios/scripts/gen.sh' first"
else
    # Required keys per Apple App Review Guidelines §5 + §28.5
    REQUIRED_KEYS="
NSCameraUsageDescription
NSPhotoLibraryUsageDescription
NSMicrophoneUsageDescription
NSFaceIDUsageDescription
NSLocationWhenInUseUsageDescription
NSContactsUsageDescription
NSBluetoothAlwaysUsageDescription
"
    for KEY in $REQUIRED_KEYS; do
        KEY="$(echo "${KEY}" | tr -d '[:space:]')"
        [ -z "${KEY}" ] && continue
        if grep -q "<key>${KEY}</key>" "${INFO_PLIST}"; then
            pass "Info.plist has ${KEY}"
        else
            fail "Info.plist MISSING ${KEY}"
        fi
    done

    # Warn about NSPhotoLibraryAddUsageDescription (strongly recommended but not blocking)
    if grep -q "<key>NSPhotoLibraryAddUsageDescription</key>" "${INFO_PLIST}"; then
        pass "Info.plist has NSPhotoLibraryAddUsageDescription"
    else
        warn "Info.plist missing NSPhotoLibraryAddUsageDescription (needed if saving to photo library)"
    fi

    # Export compliance — must be present and set to false
    if grep -q "<key>ITSAppUsesNonExemptEncryption</key>" "${INFO_PLIST}"; then
        # Check the value is <false/>
        # Use awk to get the value following the key
        VALUE=$(awk '/<key>ITSAppUsesNonExemptEncryption<\/key>/{getline; print}' "${INFO_PLIST}" | tr -d '[:space:]')
        if [ "${VALUE}" = "<false/>" ]; then
            pass "Info.plist ITSAppUsesNonExemptEncryption = false"
        else
            fail "Info.plist ITSAppUsesNonExemptEncryption is not <false/> — got: ${VALUE}"
        fi
    else
        fail "Info.plist MISSING ITSAppUsesNonExemptEncryption key (required for export compliance)"
    fi

    # NSAllowsArbitraryLoads must NOT be present (or must be false)
    if grep -q "NSAllowsArbitraryLoads" "${INFO_PLIST}"; then
        fail "Info.plist contains NSAllowsArbitraryLoads — ATS must not be disabled"
    else
        pass "Info.plist does not disable ATS (NSAllowsArbitraryLoads absent)"
    fi
fi

# -----------------------------------------------------------------------
# 2. Private API references
# -----------------------------------------------------------------------
section "2. Private API references"

if [ ! -d "${SOURCES_DIR}" ]; then
    warn "Sources directory not found at ${SOURCES_DIR} — skipping source checks"
else
    # Known private APIs that trigger App Review rejection
    PRIVATE_APIS="
_setJETSAMPriority
_UIAlertControllerView
UITouchesEvent
UIApplicationMainEventQueue
_BSMachError
_UIWebViewScrollView
SpringBoardServices
MobileGestalt
MobileInstallation
SBSSBApplicationController
rbCallEntryFromStartAddress
"
    # Specific dangerous sysctl calls (fingerprinting)
    # sysctl by itself is OK; sysctl(KERN_PROC_ALL) is private use
    PRIVATE_SYSCTL_PATTERN="KERN_PROC_ALL\|sysctl.*net\.inet\|hw\.machine.*sysctl"

    FOUND_PRIVATE=0
    for API in $PRIVATE_APIS; do
        API="$(echo "${API}" | tr -d '[:space:]')"
        [ -z "${API}" ] && continue
        RESULTS=$(grep -r "${API}" "${SOURCES_DIR}" --include="*.swift" --include="*.m" --include="*.mm" -l 2>/dev/null | grep -v "/${SOURCES_EXCLUDE}/")
        if [ -n "${RESULTS}" ]; then
            fail "Private API '${API}' found in: ${RESULTS}"
            FOUND_PRIVATE=1
        fi
    done

    # Sysctl pattern check
    SYSCTL_RESULTS=$(grep -r "${PRIVATE_SYSCTL_PATTERN}" "${SOURCES_DIR}" --include="*.swift" --include="*.m" -l 2>/dev/null | grep -v "/${SOURCES_EXCLUDE}/")
    if [ -n "${SYSCTL_RESULTS}" ]; then
        fail "Potentially private sysctl usage found in: ${SYSCTL_RESULTS}"
        FOUND_PRIVATE=1
    fi

    if [ "${FOUND_PRIVATE}" -eq 0 ]; then
        pass "No known private API references found in Packages/"
    fi
fi

# -----------------------------------------------------------------------
# 3. Debug-only code in release paths
# -----------------------------------------------------------------------
section "3. Debug-only print statements outside #if DEBUG"

if [ -d "${SOURCES_DIR}" ]; then
    # Find Swift files with bare print() calls outside #if DEBUG blocks.
    # Strategy: flag files that contain print() but do NOT have any #if DEBUG.
    # This is a heuristic — false positives possible in files that have
    # print() inside a #if DEBUG block plus other content. Treat as WARN.
    PRINT_FILES=$(grep -r "^[[:space:]]*print(" "${SOURCES_DIR}" --include="*.swift" -l 2>/dev/null | grep -v "/${SOURCES_EXCLUDE}/")
    if [ -n "${PRINT_FILES}" ]; then
        for F in $PRINT_FILES; do
            if grep -q "#if DEBUG" "${F}"; then
                # File has #if DEBUG — assume guarded; issue warning for manual review
                warn "print() in ${F} — verify it is inside a #if DEBUG block"
            else
                fail "print() without #if DEBUG guard in ${F}"
            fi
        done
    else
        pass "No bare print() statements found in Packages/"
    fi

    # Also flag NSLog outside #if DEBUG
    NSLOG_FILES=$(grep -r "NSLog(" "${SOURCES_DIR}" --include="*.swift" --include="*.m" -l 2>/dev/null | grep -v "/${SOURCES_EXCLUDE}/")
    if [ -n "${NSLOG_FILES}" ]; then
        for F in $NSLOG_FILES; do
            if grep -q "#if DEBUG" "${F}"; then
                warn "NSLog() in ${F} — verify it is inside a #if DEBUG block"
            else
                fail "NSLog() without #if DEBUG guard in ${F}"
            fi
        done
    else
        pass "No NSLog() statements found in Packages/"
    fi
fi

# -----------------------------------------------------------------------
# 4. Hardcoded credentials
# -----------------------------------------------------------------------
section "4. Hardcoded credentials"

if [ -d "${SOURCES_DIR}" ]; then
    CRED_PATTERNS="
Bearer [A-Za-z0-9]
api_key=
apikey=
Authorization: Basic
-----BEGIN RSA PRIVATE KEY-----
-----BEGIN PRIVATE KEY-----
sk_live_
sk_test_
password = \"
secret = \"
token = \"[A-Za-z0-9]
"
    FOUND_CREDS=0
    while IFS= read -r PATTERN; do
        PATTERN="$(echo "${PATTERN}" | tr -d '\n')"
        [ -z "${PATTERN}" ] && continue
        RESULTS=$(grep -r "${PATTERN}" "${SOURCES_DIR}" --include="*.swift" --include="*.m" --include="*.plist" -l 2>/dev/null | grep -v "/${SOURCES_EXCLUDE}/")
        if [ -n "${RESULTS}" ]; then
            fail "Potential hardcoded credential pattern '${PATTERN}' found in: ${RESULTS}"
            FOUND_CREDS=1
        fi
    done << 'EOF'
Bearer [A-Za-z0-9]
api_key=
apikey=
Authorization: Basic
-----BEGIN RSA PRIVATE KEY-----
-----BEGIN PRIVATE KEY-----
sk_live_
sk_test_
password = "
secret = "
EOF

    # Also check App/Resources/ (xcconfig, plists)
    RESOURCES_DIR="${IOS_DIR}/App/Resources"
    if [ -d "${RESOURCES_DIR}" ]; then
        RESULTS=$(grep -r "api_key\|Bearer \|secret.*=.*\"[A-Za-z0-9]" "${RESOURCES_DIR}" --include="*.plist" --include="*.xcconfig" -l 2>/dev/null | grep -v "/${SOURCES_EXCLUDE}/")
        if [ -n "${RESULTS}" ]; then
            fail "Potential hardcoded credential in App/Resources/: ${RESULTS}"
            FOUND_CREDS=1
        fi
    fi

    if [ "${FOUND_CREDS}" -eq 0 ]; then
        pass "No hardcoded credential patterns found"
    fi
fi

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
section "Summary"

echo "FAIL: ${FAIL_COUNT}  WARN: ${WARN_COUNT}" | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

if [ "${FAIL_COUNT}" -gt 0 ]; then
    printf "${RED}RESULT: FAILED (${FAIL_COUNT} issue(s) must be fixed before App Store submission)${RST}\n" | tee -a "${REPORT_FILE}"
    echo "" | tee -a "${REPORT_FILE}"
    echo "Report saved to: ${REPORT_FILE}"
    echo "See docs/app-review.md for remediation guidance."
    exit 1
else
    printf "${GRN}RESULT: PASSED${RST}\n" | tee -a "${REPORT_FILE}"
    if [ "${WARN_COUNT}" -gt 0 ]; then
        printf "${YLW}  (${WARN_COUNT} warning(s) — review manually before submission)${RST}\n" | tee -a "${REPORT_FILE}"
    fi
    echo "" | tee -a "${REPORT_FILE}"
    echo "Report saved to: ${REPORT_FILE}"
    exit 0
fi
