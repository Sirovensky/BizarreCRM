#!/usr/bin/env bash
# ios/scripts/rtl-lint.sh
#
# RTL layout anti-pattern audit for BizarreCRM iOS.
# Bash 3.x compatible (macOS default shell).
#
# Checks:
#   1. .padding(.left, ...)  — must use .leading not .left (fixed physical edge)
#   2. .padding(.right, ...) — must use .trailing not .right (fixed physical edge)
#   3. .frame(maxWidth: ...) or explicit width + .environment(\.layoutDirection, .leftToRight)
#      — hard-wired LTR env overrides system direction
#   4. TextField without .multilineTextAlignment(.leading) or .multilineTextAlignment(.automatic)
#      — should use .automatic or .leading (bidi-safe), not hardcoded .trailing
#   5. Image(...).rotationEffect(Angle(degrees: N)) where N is non-zero — fixed-angle rotation
#      that likely does not flip in RTL; flag for review
#   6. .multilineTextAlignment(.trailing) hardcoded — may break in LTR layouts
#
# Usage:
#   bash ios/scripts/rtl-lint.sh [--baseline] [--check-regressions] [--json-only]
#                                 [--search-root <path>]
#
# Options:
#   --baseline           Write current violation count to .rtl-baseline.txt and exit 0
#   --check-regressions  Compare against baseline; fail only if count increased
#   --json-only          Print JSON report only (no human-readable output)
#   --search-root <path> Directory to search (default: ios/)
#
# Exit codes:
#   0  No violations (or baseline mode, or regression check passed)
#   1  Violations found (or regression: count increased vs baseline)
#
# §27 RTL layout checks

set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SEARCH_ROOT="$REPO_ROOT/ios"
BASELINE_FILE="$REPO_ROOT/ios/.rtl-baseline.txt"
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
    awk -v s="$start" -v e="$end" 'NR>=s && NR<=e {print}' "$file"
}

# ── Check 1 & 2: .padding(.left, ...) / .padding(.right, ...) ────────────────
# Physical edges .left / .right bypass SwiftUI bidi layout and don't flip in RTL.
# The correct approach is .leading / .trailing (logical edges).

check_physical_padding() {
    local file="$1"
    local linenum=0

    while IFS= read -r rawline; do
        linenum=$((linenum + 1))
        if echo "$rawline" | grep -qE '\.padding\s*\(\s*\.(left|right)\s*,'; then
            local snippet
            snippet="$(echo "$rawline" | sed 's/^[[:space:]]*//')"
            add_violation "physical-padding-edge" "$file" "$linenum" "$snippet"
        fi
    done < "$file"
}

# ── Check 3: Hard-wired .environment(\.layoutDirection, .leftToRight) ─────────
# Forcing LTR direction in a view overrides the system locale and breaks RTL users.
# Acceptable ONLY inside #Preview / PreviewProvider blocks — not in production views.
# We flag all occurrences and rely on the developer to confirm preview-only usage.

check_hardwired_ltr() {
    local file="$1"
    local linenum=0

    while IFS= read -r rawline; do
        linenum=$((linenum + 1))
        if echo "$rawline" | grep -qE '\.environment\s*\(\s*\\\.layoutDirection\s*,\s*\.leftToRight\s*\)'; then
            local snippet
            snippet="$(echo "$rawline" | sed 's/^[[:space:]]*//')"
            add_violation "hardwired-ltr-environment" "$file" "$linenum" "$snippet"
        fi
    done < "$file"
}

# ── Check 4: TextField without bidi-safe multilineTextAlignment ──────────────
# A TextField that does NOT have .multilineTextAlignment(.leading) or
# .multilineTextAlignment(.automatic) within ±5 lines may look wrong in RTL
# because the default system text alignment for non-primary locales varies.
# Flag TextFields that have .multilineTextAlignment(.trailing) hardcoded.

check_textfield_alignment() {
    local file="$1"
    local linenum=0

    while IFS= read -r rawline; do
        linenum=$((linenum + 1))
        if echo "$rawline" | grep -qE '^\s*TextField\s*\('; then
            local ctx
            ctx="$(context_lines "$file" "$linenum" 5)"
            if echo "$ctx" | grep -qE '\.multilineTextAlignment\s*\(\s*\.trailing\s*\)'; then
                local snippet
                snippet="$(echo "$rawline" | sed 's/^[[:space:]]*//')"
                add_violation "textfield-hardcoded-trailing-alignment" "$file" "$linenum" "$snippet"
            fi
        fi
    done < "$file"
}

# ── Check 5: Image rotationEffect with non-zero fixed degrees ─────────────────
# A fixed rotation angle does not flip in RTL. Directional icons that use
# rotationEffect must branch on layoutDirection or use flipsForRightToLeftLayoutDirection.
# Non-directional icons (clock hands, loaders) may be intentionally non-mirroring —
# developer must confirm; we flag for review.

check_rotation_effect() {
    local file="$1"
    local linenum=0

    while IFS= read -r rawline; do
        linenum=$((linenum + 1))
        # Match .rotationEffect(Angle(degrees: N)) or .rotationEffect(.degrees(N))
        # where N is non-zero — zero-degree rotation is a no-op and safe.
        if echo "$rawline" | grep -qE '\.rotationEffect\s*\('; then
            # Extract degree value — skip if it's 0 or 0.0
            local degrees
            degrees="$(echo "$rawline" | grep -oE 'degrees\s*:\s*-?[0-9]+(\.[0-9]+)?' | grep -oE '-?[0-9]+(\.[0-9]+)?' | head -1)"
            if [ -n "$degrees" ]; then
                # Strip sign and decimal for comparison
                local abs
                abs="$(echo "$degrees" | sed 's/^-//' | cut -d'.' -f1)"
                if [ -n "$abs" ] && [ "$abs" -ne 0 ] 2>/dev/null; then
                    local ctx
                    ctx="$(context_lines "$file" "$linenum" 5)"
                    # Only flag if the file doesn't already use flipsForRightToLeftLayoutDirection
                    # or branch on layoutDirection nearby
                    if ! echo "$ctx" | grep -qE 'flipsForRightToLeftLayoutDirection|layoutDirection'; then
                        local snippet
                        snippet="$(echo "$rawline" | sed 's/^[[:space:]]*//')"
                        add_violation "fixed-rotation-not-rtl-aware" "$file" "$linenum" "$snippet"
                    fi
                fi
            fi
        fi
    done < "$file"
}

# ── Check 6: .multilineTextAlignment(.trailing) outside RTL context ───────────
# Hardcoding .trailing text alignment in a non-RTL-conditioned block produces
# right-aligned text in LTR locales, which is usually wrong.

check_hardcoded_trailing_alignment() {
    local file="$1"
    local linenum=0

    while IFS= read -r rawline; do
        linenum=$((linenum + 1))
        if echo "$rawline" | grep -qE '\.multilineTextAlignment\s*\(\s*\.trailing\s*\)'; then
            local ctx
            ctx="$(context_lines "$file" "$linenum" 8)"
            # Flag only when NOT conditioned on layoutDirection or RTL environment
            if ! echo "$ctx" | grep -qE 'layoutDirection|rightToLeft|RTLHelpers'; then
                local snippet
                snippet="$(echo "$rawline" | sed 's/^[[:space:]]*//')"
                add_violation "hardcoded-trailing-text-alignment" "$file" "$linenum" "$snippet"
            fi
        fi
    done < "$file"
}

# ── Main scan ────────────────────────────────────────────────────────────────

if [ "$JSON_ONLY" -eq 0 ]; then
    echo "BizarreCRM RTL Layout Lint"
    echo "Search root: $SEARCH_ROOT"
    echo "------------------------------------------------------------"
fi

# Find all Swift source files (skip generated / build / test support files)
SWIFT_FILES="$(find "$SEARCH_ROOT" \
    -name "*.swift" \
    -not -path "*/build/*" \
    -not -path "*/.build/*" \
    -not -path "*/DerivedData/*" \
    2>/dev/null || true)"

FILES_CHECKED=0

for f in $SWIFT_FILES; do
    FILES_CHECKED=$((FILES_CHECKED + 1))
    check_physical_padding           "$f"
    check_hardwired_ltr              "$f"
    check_textfield_alignment        "$f"
    check_rotation_effect            "$f"
    check_hardcoded_trailing_alignment "$f"
done

# ── Baseline mode ────────────────────────────────────────────────────────────

if [ "$BASELINE_MODE" -eq 1 ]; then
    echo "$VIOLATIONS_TOTAL" > "$BASELINE_FILE"
    echo "RTL baseline written to $BASELINE_FILE ($VIOLATIONS_TOTAL violations recorded)."
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
        echo "RTL lint PASSED. No violations found."
    else
        echo "RTL lint FAILED. Review violations above before merging."
    fi
fi

# ── Regression check ─────────────────────────────────────────────────────────

if [ "$REGRESSION_MODE" -eq 1 ]; then
    if [ ! -f "$BASELINE_FILE" ]; then
        echo "ERROR: No baseline file at $BASELINE_FILE. Run: bash ios/scripts/rtl-lint.sh --baseline" >&2
        exit 1
    fi
    BASELINE_COUNT="$(cat "$BASELINE_FILE" | tr -d '[:space:]')"
    if [ "$VIOLATIONS_TOTAL" -gt "$BASELINE_COUNT" ]; then
        echo "RTL REGRESSION: $VIOLATIONS_TOTAL violations (was $BASELINE_COUNT in baseline). Fix new violations before merging." >&2
        exit 1
    fi
    if [ "$JSON_ONLY" -eq 0 ]; then
        echo "RTL regression check PASSED: $VIOLATIONS_TOTAL violations (baseline: $BASELINE_COUNT)."
    fi
    exit 0
fi

[ "$VIOLATIONS_TOTAL" -eq 0 ] && exit 0 || exit 1
