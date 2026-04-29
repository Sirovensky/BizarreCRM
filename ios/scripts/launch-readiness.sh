#!/usr/bin/env bash
# launch-readiness.sh — BizarreCRM pre-submission gate check
# Runs a series of non-build checks and reports PASS / FAIL per item.
# Exit 0 only when every gate is green.
# Usage: ./scripts/launch-readiness.sh [--fix]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX_MODE=false
[[ "${1:-}" == "--fix" ]] && FIX_MODE=true

PASS=0
FAIL=0

pass() { echo "  PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }
section() { echo ""; echo "=== $1 ==="; }

# ── 1. PrivacyInfo.xcprivacy ────────────────────────────────────────────────
section "Privacy manifest"
PRIVACY_FILE="$REPO_ROOT/App/Resources/PrivacyInfo.xcprivacy"
if [[ -f "$PRIVACY_FILE" ]]; then
    pass "PrivacyInfo.xcprivacy exists"
    # Must not declare NSPrivacyTracking = true
    if grep -q "<true/>" "$PRIVACY_FILE" && \
       grep -B1 "<true/>" "$PRIVACY_FILE" | grep -q "NSPrivacyTracking"; then
        fail "NSPrivacyTracking is TRUE — must be false"
    else
        pass "NSPrivacyTracking = false"
    fi
    # NSPrivacyTrackingDomains must be empty
    if python3 -c "
import plistlib, sys
with open('$PRIVACY_FILE', 'rb') as f:
    d = plistlib.load(f)
domains = d.get('NSPrivacyTrackingDomains', [])
sys.exit(0 if len(domains) == 0 else 1)
" 2>/dev/null; then
        pass "NSPrivacyTrackingDomains is empty"
    else
        fail "NSPrivacyTrackingDomains is non-empty"
    fi
else
    fail "PrivacyInfo.xcprivacy missing at $PRIVACY_FILE"
fi

# ── 2. Info.plist purpose strings ───────────────────────────────────────────
section "Info.plist usage descriptions"
INFO_PLIST="$REPO_ROOT/App/Resources/Info.plist"
REQUIRED_KEYS=(
    NSCameraUsageDescription
    NSPhotoLibraryUsageDescription
    NSMicrophoneUsageDescription
    NSBluetoothAlwaysUsageDescription
    NSLocalNetworkUsageDescription
    NFCReaderUsageDescription
    NSFaceIDUsageDescription
    NSLocationWhenInUseUsageDescription
)
if [[ -f "$INFO_PLIST" ]]; then
    for key in "${REQUIRED_KEYS[@]}"; do
        if grep -q "$key" "$INFO_PLIST"; then
            pass "$key present"
        else
            fail "$key MISSING from Info.plist"
        fi
    done
else
    fail "Info.plist not found at $INFO_PLIST"
fi

# ── 3. No hardcoded credentials ─────────────────────────────────────────────
section "Credential scan"
if "$REPO_ROOT/scripts/app-review-lint.sh" 2>/dev/null | grep -q "FAIL.*credential"; then
    fail "Hardcoded credentials detected"
else
    pass "No hardcoded credentials found"
fi

# ── 4. SDK sovereignty ───────────────────────────────────────────────────────
section "SDK sovereignty"
if "$REPO_ROOT/scripts/sdk-ban.sh" 2>/dev/null; then
    pass "SDK ban check passed"
else
    fail "Forbidden SDK imports detected — run scripts/sdk-ban.sh for details"
fi

# ── 5. Debug prints ─────────────────────────────────────────────────────────
section "Debug print scan"
PRINT_COUNT=$(grep -rn --include="*.swift" \
    --exclude-dir=".build" --exclude-dir="checkouts" \
    "^\s*print(" "$REPO_ROOT/App" "$REPO_ROOT/Packages" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$PRINT_COUNT" -eq 0 ]]; then
    pass "No bare print() calls in first-party sources"
else
    fail "$PRINT_COUNT bare print() call(s) found — replace with Logger or #if DEBUG guard"
fi

# ── 6. Fastlane metadata ────────────────────────────────────────────────────
section "Fastlane metadata"
META_DIR="$REPO_ROOT/fastlane/metadata/en-US"
if [[ -d "$META_DIR" ]]; then
    for f in name.txt description.txt keywords.txt; do
        if [[ -f "$META_DIR/$f" && -s "$META_DIR/$f" ]]; then
            pass "metadata/$f populated"
        else
            fail "metadata/$f missing or empty"
        fi
    done
else
    fail "fastlane/metadata/en-US/ directory missing"
fi

# ── 7. Snapshots (screenshot stubs) ─────────────────────────────────────────
section "Screenshot stubs"
SNAPFILE="$REPO_ROOT/fastlane/Snapfile"
if [[ -f "$SNAPFILE" ]]; then
    pass "Snapfile exists"
else
    fail "Snapfile missing — run scripts/launch-readiness.sh after setting up fastlane snapshot"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────"
echo "Launch readiness: $PASS passed, $FAIL failed"
echo "────────────────────────────────────────────"
if [[ "$FAIL" -gt 0 ]]; then
    echo "Not ready for App Store submission. Fix failing items first."
    exit 1
fi
echo "All checks passed. Proceed to App Store submission."
exit 0
