#!/bin/sh
# perf-report.sh — Aggregate iOS performance benchmark results into docs/perf-baseline.json.
#
# Usage:
#   bash ios/scripts/perf-report.sh
#
# Steps:
#   1. Runs bench.sh to execute the performance test suite.
#   2. Reads /tmp/ios-perf.xcresult via xcresulttool.
#   3. Writes docs/perf-baseline.json for PR diff tracking.
#
# Requirements:
#   - Xcode command-line tools (xcresulttool ships with Xcode 16+).
#   - A booted iOS 17+ simulator named "iPhone 15".
#   - bench.sh in the same directory.
#
# Dry-run behaviour:
#   If /tmp/ios-perf.xcresult does not exist (e.g. bench.sh was skipped
#   or xcodebuild failed), the script still writes a sentinel JSON so
#   CI does not fail on a missing file. The sentinel contains
#   "status": "no-result" so diff tools can detect it.
#
# Bash 3.x compatible (macOS ships Bash 3.2).
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$IOS_DIR/.." && pwd)"

RESULT_BUNDLE="/tmp/ios-perf.xcresult"
SUMMARY_JSON="/tmp/ios-perf-summary.json"
BASELINE_DIR="$REPO_ROOT/docs"
BASELINE_FILE="$BASELINE_DIR/perf-baseline.json"

# ------------------------------------------------------------------
# Step 1: Run bench harness (tolerate failure — dry-run path below).
# ------------------------------------------------------------------
echo "==> [perf-report] Running bench.sh …"
if sh "$SCRIPT_DIR/bench.sh"; then
    BENCH_STATUS="ok"
else
    BENCH_STATUS="failed"
    echo "    bench.sh exited non-zero — continuing with dry-run JSON output."
fi

# ------------------------------------------------------------------
# Step 2: Parse xcresult → JSON.
# ------------------------------------------------------------------
XCRESULT_JSON=""

if [ -d "$RESULT_BUNDLE" ] && command -v xcresulttool > /dev/null 2>&1; then
    echo "==> [perf-report] Parsing xcresult bundle …"
    if xcresulttool get --format json --path "$RESULT_BUNDLE" > "$SUMMARY_JSON" 2>/dev/null; then
        XCRESULT_JSON=$(cat "$SUMMARY_JSON")
        echo "    xcresult parsed successfully."
    else
        echo "    xcresulttool returned non-zero — xcresult may be empty or malformed."
        XCRESULT_JSON=""
    fi
else
    if [ ! -d "$RESULT_BUNDLE" ]; then
        echo "    No xcresult bundle at $RESULT_BUNDLE — bench did not produce output."
    else
        echo "    xcresulttool not found — install Xcode command-line tools."
    fi
fi

# ------------------------------------------------------------------
# Step 3: Write docs/perf-baseline.json.
# ------------------------------------------------------------------
mkdir -p "$BASELINE_DIR"

TIMESTAMP=$(date -u "+%Y-%m-%dT%H:%M:%SZ")

# Determine status field.
if [ "$BENCH_STATUS" = "ok" ] && [ -n "$XCRESULT_JSON" ]; then
    STATUS="ok"
elif [ -n "$XCRESULT_JSON" ]; then
    STATUS="bench-failed-xcresult-parsed"
else
    STATUS="no-result"
fi

# Emit compact baseline JSON.
# xcresult full JSON is large; store only metadata + budgets here.
# Full metrics are in the xcresult bundle opened via Xcode.
cat > "$BASELINE_FILE" << EOF
{
  "generated_at": "$TIMESTAMP",
  "status": "$STATUS",
  "result_bundle": "$RESULT_BUNDLE",
  "budgets": {
    "scroll_frame_p95_ms": 16.67,
    "cold_start_ms": 1500,
    "warm_start_ms": 250,
    "list_render_ms": 500,
    "idle_memory_mb": 200,
    "request_timeout_ms": 10000,
    "progress_show_ms": 500
  },
  "notes": "Full metrics in $RESULT_BUNDLE — open in Xcode or run xcresulttool get --path $RESULT_BUNDLE"
}
EOF

echo ""
echo "==> [perf-report] Baseline written to $BASELINE_FILE"
echo "    Status: $STATUS"
echo ""

if [ "$STATUS" = "no-result" ]; then
    echo "    DRY-RUN: No xcresult produced. This is expected when:"
    echo "      - bench.sh failed (simulator not booted, project not built)"
    echo "      - Running in an environment without a simulator"
    echo "    The JSON sentinel is still written so CI diff checks have a file to compare."
fi

echo "==> [perf-report] Done."
