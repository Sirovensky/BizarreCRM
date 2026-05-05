#!/usr/bin/env bash
# bench.sh — Run the iOS scroll performance benchmark harness.
#
# Usage:
#   bash ios/scripts/bench.sh
#
# Results: /tmp/ios-perf.xcresult
# Pass criterion: p95 frame time < 16.67 ms (= 60 fps) on iPhone SE.
#
# NOTE: This script will fail until the harness-mode repositories are wired in
# AppServices.swift. See ios/Tests/Performance/README.md for the TODO wiring
# instructions. The gate is intentionally documented-not-implemented per §29.
set -euo pipefail

cd "$(dirname "$0")/.."

RESULT_BUNDLE="/tmp/ios-perf.xcresult"

# Remove stale result bundle so xcresulttool always reads fresh data.
rm -rf "$RESULT_BUNDLE"

echo "==> Running iOS performance benchmarks…"

xcodebuild test \
  -project BizarreCRM.xcodeproj \
  -scheme BizarreCRM \
  -destination "platform=iOS Simulator,name=iPhone 15,OS=latest" \
  -only-testing:BizarreCRMUITests/TicketListScrollTests \
  -only-testing:BizarreCRMUITests/CustomerListScrollTests \
  -only-testing:BizarreCRMUITests/InventoryListScrollTests \
  -only-testing:BizarreCRMUITests/InvoiceListScrollTests \
  -only-testing:BizarreCRMUITests/SmsThreadListScrollTests \
  -resultBundlePath "$RESULT_BUNDLE" \
  | xcpretty --no-color

echo ""
echo "==> Results at $RESULT_BUNDLE"
echo ""

# Emit a JSON summary if xcresulttool is available (Xcode 16+).
if command -v xcresulttool &>/dev/null; then
  SUMMARY_JSON="/tmp/ios-perf-summary.json"
  xcresulttool get --format json --path "$RESULT_BUNDLE" > "$SUMMARY_JSON" 2>/dev/null || true
  if [ -f "$SUMMARY_JSON" ]; then
    echo "==> JSON summary at $SUMMARY_JSON"
  fi
fi

echo "==> Done. Open $RESULT_BUNDLE in Xcode to inspect per-metric graphs."
echo "    Phase 3 gate: p95 scroll frame time < 16.67 ms (≥ 60 fps on iPhone SE)."
echo "    ProMotion target: < 8.33 ms (≥ 120 fps on iPad Pro M-series)."
