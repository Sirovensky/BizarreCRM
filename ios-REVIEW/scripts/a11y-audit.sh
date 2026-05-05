#!/usr/bin/env bash
# ios/scripts/a11y-audit.sh
#
# Automated accessibility anti-pattern audit for BizarreCRM iOS.
# Bash 3.x compatible (macOS default shell).
#
# Checks:
#   1. Button(...) without .accessibilityLabel within ±5 lines
#   2. Image(systemName:) without .accessibilityHidden(true) OR .accessibilityLabel
#   3. TextField(...) without .accessibilityLabel within ±5 lines
#   4. .onTapGesture on Rectangle/Circle (tap target heuristic)
#   5. .font(.system(size: N)) where N < 14 or > 24 (fixed size, ignores Dynamic Type)
#   6. .animation(...) in files that do NOT reference accessibilityReduceMotion
#
# Usage:
#   bash ios/scripts/a11y-audit.sh [--baseline] [--json-only] [--search-root <path>]
#
# Options:
#   --baseline           Write current violation count to .a11y-baseline.txt and exit 0
#   --check-regressions  Compare against baseline; fail only if count increased
#   --json-only          Print JSON report only (no human-readable output)
#   --search-root <path> Directory to search (default: ios/)
#
# Exit codes:
#   0  No violations (or baseline mode, or regression check passed)
#   1  Violations found (or regression: count increased vs baseline)
#
# §29 Automated a11y audit CI

set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SEARCH_ROOT="$REPO_ROOT/ios"
BASELINE_FILE="$REPO_ROOT/ios/.a11y-baseline.txt"
JSON_ONLY=0
BASELINE_MODE=0
REGRESSION_MODE=0

# ── Arg parsing ──────────────────────────────────────────────────────────────

while [ $# -gt 0 ]; do
    case "$1" in
        --baseline)             BASELINE_MODE=1;    shift ;;
        --check-regressions)    REGRESSION_MODE=1;  shift ;;
        --json-only)            JSON_ONLY=1;         shift ;;
        --search-root)          SEARCH_ROOT="$2";   shift 2 ;;
        *)                      echo "Unknown flag: $1" >&2; exit 2 ;;
    esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────

VIOLATIONS_TOTAL=0
JSON_VIOLATIONS=""
HUMAN_REPORT=""

add_violation() {
    local check="$1"
    local file="$2"
    local line="$3"
    local snippet="$4"

    VIOLATIONS_TOTAL=$((VIOLATIONS_TOTAL + 1))

    local entry
    entry="$(printf '{"check":"%s","file":"%s","line":%s,"snippet":"%s"}' \
        "$check" "$file" "$line" "$(echo "$snippet" | tr '"' "'")")"

    if [ -n "$JSON_VIOLATIONS" ]; then
        JSON_VIOLATIONS="$JSON_VIOLATIONS,$entry"
    else
        JSON_VIOLATIONS="$entry"
    fi

    if [ "$JSON_ONLY" -eq 0 ]; then
        HUMAN_REPORT="$HUMAN_REPORT
[$check] $file:$line
  $snippet"
    fi
}

# Returns lines around a given line number (±N) from a file as a single string.
context_lines() {
    local file="$1"
    local center="$2"
    local radius="${3:-5}"
    local start=$(( center - radius ))
    local end=$(( center + radius ))
    [ "$start" -lt 1 ] && start=1
    # awk: print lines $start..$end
    awk -v s="$start" -v e="$end" 'NR>=s && NR<=e {print}' "$file"
}

# ── Check 1: Button without accessibilityLabel ────────────────────────────────

check_button_labels() {
    local file="$1"
    local linenum=0

    while IFS= read -r rawline; do
        linenum=$((linenum + 1))
        # Match Button( or Button(action: or Button(role: — SwiftUI button initializers
        if echo "$rawline" | grep -qE '^\s*Button\s*\('; then
            local ctx
            ctx="$(context_lines "$file" "$linenum" 5)"
            if ! echo "$ctx" | grep -qE '\.accessibilityLabel\s*\('; then
                local snippet
                snippet="$(echo "$rawline" | sed 's/^[[:space:]]*//')"
                add_violation "button-missing-a11y-label" "$file" "$linenum" "$snippet"
            fi
        fi
    done < "$file"
}

# ── Check 2: Image(systemName:) without accessibilityHidden or accessibilityLabel ──

check_image_labels() {
    local file="$1"
    local linenum=0

    while IFS= read -r rawline; do
        linenum=$((linenum + 1))
        if echo "$rawline" | grep -qE 'Image\s*\(\s*systemName\s*:'; then
            local ctx
            ctx="$(context_lines "$file" "$linenum" 5)"
            if ! echo "$ctx" | grep -qE '\.accessibilityHidden\s*\(true\)|\.accessibilityLabel\s*\('; then
                local snippet
                snippet="$(echo "$rawline" | sed 's/^[[:space:]]*//')"
                add_violation "image-missing-a11y" "$file" "$linenum" "$snippet"
            fi
        fi
    done < "$file"
}

# ── Check 3: TextField without accessibilityLabel ────────────────────────────

check_textfield_labels() {
    local file="$1"
    local linenum=0

    while IFS= read -r rawline; do
        linenum=$((linenum + 1))
        if echo "$rawline" | grep -qE '^\s*TextField\s*\('; then
            local ctx
            ctx="$(context_lines "$file" "$linenum" 5)"
            if ! echo "$ctx" | grep -qE '\.accessibilityLabel\s*\('; then
                local snippet
                snippet="$(echo "$rawline" | sed 's/^[[:space:]]*//')"
                add_violation "textfield-missing-a11y-label" "$file" "$linenum" "$snippet"
            fi
        fi
    done < "$file"
}

# ── Check 4: .onTapGesture on Rectangle/Circle ───────────────────────────────
# Heuristic: a Rectangle or Circle followed (within 5 lines) by .onTapGesture
# without a .frame specifying ≥44 nearby signals a small tap target.

check_tap_targets() {
    local file="$1"
    local linenum=0

    while IFS= read -r rawline; do
        linenum=$((linenum + 1))
        if echo "$rawline" | grep -qE '^\s*(Rectangle|Circle)\s*\(\s*\)'; then
            local ctx
            ctx="$(context_lines "$file" "$linenum" 6)"
            if echo "$ctx" | grep -qE '\.onTapGesture\s*\('; then
                # Only flag if there's no .frame(... 44 ...) nearby
                if ! echo "$ctx" | grep -qE '\.frame\s*\([^)]*4[4-9][^)]*\)|\.frame\s*\([^)]*[5-9][0-9][^)]*\)'; then
                    local snippet
                    snippet="$(echo "$rawline" | sed 's/^[[:space:]]*//')"
                    add_violation "small-tap-target-heuristic" "$file" "$linenum" "$snippet"
                fi
            fi
        fi
    done < "$file"
}

# ── Check 5: Fixed .font(.system(size: N)) outside Dynamic Type ──────────────
# Flags .font(.system(size: N)) where N is a literal < 14 or > 24.

check_fixed_font_sizes() {
    local file="$1"
    local linenum=0

    while IFS= read -r rawline; do
        linenum=$((linenum + 1))
        # Extract size number from .font(.system(size: N)) or .font(.system(size: N,
        if echo "$rawline" | grep -qE '\.font\s*\(\s*\.system\s*\(\s*size\s*:\s*[0-9]+'; then
            local size
            size="$(echo "$rawline" | grep -oE 'size\s*:\s*[0-9]+' | grep -oE '[0-9]+' | head -1)"
            if [ -n "$size" ]; then
                if [ "$size" -lt 14 ] || [ "$size" -gt 24 ]; then
                    local snippet
                    snippet="$(echo "$rawline" | sed 's/^[[:space:]]*//')"
                    add_violation "fixed-font-size-ignores-dynamic-type" "$file" "$linenum" "$snippet (size=$size)"
                fi
            fi
        fi
    done < "$file"
}

# ── Check 6: .animation(...) in files without Reduce Motion check ─────────────

check_reduce_motion() {
    local file="$1"

    # If file has .animation( calls, it should also reference accessibilityReduceMotion
    if grep -qE '\.animation\s*\(' "$file"; then
        if ! grep -qE 'accessibilityReduceMotion|reduceMotion' "$file"; then
            # Find first .animation( line
            local linenum
            linenum="$(grep -nE '\.animation\s*\(' "$file" | head -1 | cut -d: -f1)"
            local snippet
            snippet="$(grep -nE '\.animation\s*\(' "$file" | head -1 | cut -d: -f2- | sed 's/^[[:space:]]*//')"
            add_violation "animation-without-reduce-motion-check" "$file" "$linenum" "$snippet"
        fi
    fi
}

# ── Main scan ────────────────────────────────────────────────────────────────

if [ "$JSON_ONLY" -eq 0 ]; then
    echo "BizarreCRM A11y Audit"
    echo "Search root: $SEARCH_ROOT"
    echo "------------------------------------------------------------"
fi

# Find all SwiftUI Swift files (skip generated / build / test files)
SWIFT_FILES="$(find "$SEARCH_ROOT" \
    -name "*.swift" \
    -not -path "*/build/*" \
    -not -path "*/.build/*" \
    -not -path "*/DerivedData/*" \
    -not -path "*Tests*" \
    2>/dev/null || true)"

FILES_CHECKED=0

for f in $SWIFT_FILES; do
    FILES_CHECKED=$((FILES_CHECKED + 1))
    check_button_labels    "$f"
    check_image_labels     "$f"
    check_textfield_labels "$f"
    check_tap_targets      "$f"
    check_fixed_font_sizes "$f"
    check_reduce_motion    "$f"
done

# ── Baseline mode ────────────────────────────────────────────────────────────

if [ "$BASELINE_MODE" -eq 1 ]; then
    echo "$VIOLATIONS_TOTAL" > "$BASELINE_FILE"
    echo "Baseline written to $BASELINE_FILE ($VIOLATIONS_TOTAL violations recorded)."
    exit 0
fi

# ── Output ───────────────────────────────────────────────────────────────────

JSON_REPORT="$(printf '{"violations_total":%d,"files_checked":%d,"violations":[%s]}' \
    "$VIOLATIONS_TOTAL" "$FILES_CHECKED" "$JSON_VIOLATIONS")"

echo "$JSON_REPORT"

if [ "$JSON_ONLY" -eq 0 ] && [ -n "$HUMAN_REPORT" ]; then
    echo ""
    echo "Violations:"
    echo "$HUMAN_REPORT"
    echo ""
    echo "------------------------------------------------------------"
    echo "Total violations: $VIOLATIONS_TOTAL across $FILES_CHECKED files checked."
fi

if [ "$JSON_ONLY" -eq 0 ]; then
    if [ "$VIOLATIONS_TOTAL" -eq 0 ]; then
        echo "A11y audit PASSED. No violations found."
    else
        echo "A11y audit FAILED. Fix the violations above before merging."
    fi
fi

# ── Regression check ─────────────────────────────────────────────────────────

if [ "$REGRESSION_MODE" -eq 1 ]; then
    if [ ! -f "$BASELINE_FILE" ]; then
        echo "ERROR: No baseline file at $BASELINE_FILE. Run: bash ios/scripts/a11y-audit.sh --baseline" >&2
        exit 1
    fi
    BASELINE_COUNT="$(cat "$BASELINE_FILE" | tr -d '[:space:]')"
    if [ "$VIOLATIONS_TOTAL" -gt "$BASELINE_COUNT" ]; then
        echo "A11y REGRESSION: $VIOLATIONS_TOTAL violations (was $BASELINE_COUNT in baseline). Fix new violations before merging." >&2
        exit 1
    fi
    if [ "$JSON_ONLY" -eq 0 ]; then
        echo "A11y regression check PASSED: $VIOLATIONS_TOTAL violations (baseline: $BASELINE_COUNT)."
    fi
    exit 0
fi

[ "$VIOLATIONS_TOTAL" -eq 0 ] && exit 0 || exit 1
