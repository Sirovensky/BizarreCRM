#!/usr/bin/env bash
# smoke-test-runner.sh — BizarreCRM targeted smoke test runner
# Runs the fast subset of tests that must pass before any TestFlight upload.
# Does NOT replace the full CI suite — it is a local pre-flight sanity check.
# Usage: ./scripts/smoke-test-runner.sh [--scheme <scheme>] [--os <os-version>]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="BizarreCRM"
OS_VERSION="18.0"
DEVICE="iPhone 16 Pro"
RESULTS_DIR="/tmp/smoke-results"

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --scheme) SCHEME="$2"; shift 2 ;;
        --os)     OS_VERSION="$2"; shift 2 ;;
        --device) DEVICE="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

DESTINATION="platform=iOS Simulator,name=${DEVICE},OS=${OS_VERSION}"
mkdir -p "$RESULTS_DIR"

echo "BizarreCRM smoke-test runner"
echo "Scheme:  $SCHEME"
echo "Device:  $DEVICE (iOS $OS_VERSION)"
echo "Results: $RESULTS_DIR"
echo ""

# ── Helper ───────────────────────────────────────────────────────────────────
run_test_class() {
    local label="$1"
    local test_id="$2"
    local result_path="$RESULTS_DIR/${label// /_}.xcresult"
    echo -n "  Running $label ... "
    if xcodebuild test \
        -project "$REPO_ROOT/BizarreCRM.xcodeproj" \
        -scheme "$SCHEME" \
        -destination "$DESTINATION" \
        -only-testing:"$test_id" \
        -resultBundlePath "$result_path" \
        -quiet 2>/dev/null; then
        echo "PASS"
        return 0
    else
        echo "FAIL  (see $result_path)"
        return 1
    fi
}

PASS=0
FAIL=0

# ── Gate 0: xcodegen project up to date ─────────────────────────────────────
echo "=== Gate 0: project.yml freshness ==="
if command -v xcodegen &>/dev/null; then
    if xcodegen generate --quiet 2>/dev/null; then
        echo "  PASS  xcodegen project regenerated cleanly"
        PASS=$((PASS+1))
    else
        echo "  FAIL  xcodegen generate failed"
        FAIL=$((FAIL+1))
    fi
else
    echo "  SKIP  xcodegen not installed — install via: brew install xcodegen"
fi

# ── Gate 1: Swift package resolution ────────────────────────────────────────
echo ""
echo "=== Gate 1: SPM resolution ==="
if xcodebuild -resolvePackageDependencies \
    -project "$REPO_ROOT/BizarreCRM.xcodeproj" \
    -quiet 2>/dev/null; then
    echo "  PASS  Package dependencies resolved"
    PASS=$((PASS+1))
else
    echo "  FAIL  SPM resolution failed"
    FAIL=$((FAIL+1))
fi

# ── Gate 2: Core smoke tests (in-memory DB, offline sync) ────────────────────
echo ""
echo "=== Gate 2: Core smoke tests ==="
if run_test_class "SmokeTests" "BizarreCRMTests/SmokeTests"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
fi

# ── Gate 3: Auth smoke ───────────────────────────────────────────────────────
echo ""
echo "=== Gate 3: Auth smoke ==="
if run_test_class "AuthTests" "BizarreCRMTests/AuthTests"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
fi

# ── Gate 4: SDK ban lint ─────────────────────────────────────────────────────
echo ""
echo "=== Gate 4: SDK sovereignty lint ==="
if "$REPO_ROOT/scripts/sdk-ban.sh" 2>/dev/null; then
    echo "  PASS  SDK ban"
    PASS=$((PASS+1))
else
    echo "  FAIL  sdk-ban.sh found forbidden imports"
    FAIL=$((FAIL+1))
fi

# ── Gate 5: app-review lint ──────────────────────────────────────────────────
echo ""
echo "=== Gate 5: App Review lint ==="
if "$REPO_ROOT/scripts/app-review-lint.sh" 2>/dev/null; then
    echo "  PASS  app-review-lint"
    PASS=$((PASS+1))
else
    echo "  FAIL  app-review-lint.sh found issues"
    FAIL=$((FAIL+1))
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════"
echo "Smoke results: $PASS passed, $FAIL failed"
echo "════════════════════════════════════"
if [[ "$FAIL" -gt 0 ]]; then
    echo "Smoke gate FAILED. Do not upload to TestFlight."
    exit 1
fi
echo "All smoke gates GREEN. Safe to upload to TestFlight."
exit 0
