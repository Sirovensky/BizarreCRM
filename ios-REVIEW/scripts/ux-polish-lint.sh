#!/usr/bin/env bash
# ux-polish-lint.sh — §72 UX polish anti-pattern audit
#
# Greps iOS SwiftUI source for anti-patterns defined in the §72 checklist.
# Exits 0 when violations are at or below BASELINE (tracked regression).
# Exits 1 when violations EXCEED BASELINE (regression alert).
#
# Writes JSON report to ios/ux-polish-lint-report.json when --report is passed.
#
# Usage:
#   bash ios/scripts/ux-polish-lint.sh            # normal run
#   bash ios/scripts/ux-polish-lint.sh --report   # write JSON report
#
# macOS/Bash 3.x compatible — no associative arrays, no process substitution
# with mapfile.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Violation baseline — lower over time, never raise without human sign-off.
# Initial baseline captured 2026-04-20 from pre-existing codebase state.
# 36 List-without-refreshable + 87 TextField-without-submitLabel = 123.
BASELINE=123

REPORT_MODE=false
if [[ "${1:-}" == "--report" ]]; then
    REPORT_MODE=true
fi

SWIFT_SRC_DIRS=(
    "${IOS_ROOT}/App"
    "${IOS_ROOT}/Packages"
    "${IOS_ROOT}/BizarreCRMWidgets"
)

# Collect Swift source files (Bash 3.x compatible find + while loop)
SWIFT_FILES_RAW=""
for dir in "${SWIFT_SRC_DIRS[@]}"; do
    if [[ -d "${dir}" ]]; then
        while IFS= read -r -d '' f; do
            SWIFT_FILES_RAW="${SWIFT_FILES_RAW}${f}"$'\n'
        done < <(find "${dir}" -name "*.swift" \
                     -not -path "*/.build/*" \
                     -not -path "*/checkouts/*" \
                     -print0 2>/dev/null)
    fi
done

if [[ -z "${SWIFT_FILES_RAW}" ]]; then
    echo "WARNING: No Swift source files found under ${IOS_ROOT}" >&2
    echo "OK: 0 violations (no source to scan)."
    exit 0
fi

# Convert newline-delimited to array (Bash 3.x)
SWIFT_FILES=()
while IFS= read -r f; do
    [[ -n "${f}" ]] && SWIFT_FILES+=("${f}")
done <<< "${SWIFT_FILES_RAW}"

# ---------------------------------------------------------------------------
# Anti-pattern rules
# Each entry: "RULE_ID|grep_pattern|description|exclude_pattern"
# exclude_pattern is used with grep -v; use __NONE__ to skip exclusion.
# ---------------------------------------------------------------------------
# Rules are stored as parallel arrays (Bash 3.x compatible)
RULE_IDS=()
RULE_PATTERNS=()
RULE_DESCS=()
RULE_EXCLUDES=()

# 1. List without .refreshable nearby (within 20 lines)
#    Strategy: flag List( calls that don't have .refreshable in the same file.
#    We do a coarse file-level check: file contains List( but NOT .refreshable
#    Note: this is intentionally coarse — it flags files, not exact lines.
#    Detailed per-file checks are done below as special cases.

# 2. Button("Delete"...) without .role(.destructive)
RULE_IDS+=("BTN_DELETE_NO_ROLE")
RULE_PATTERNS+=('Button\("Delete')
RULE_DESCS+=('Button("Delete...") without .role(.destructive) — use Button(role: .destructive)')
RULE_EXCLUDES+=('role: .destructive')

# 3. Text("$...") with Double formatter (non-Cents)
RULE_IDS+=("MONEY_DOUBLE_FORMAT")
RULE_PATTERNS+=('Text\("\\\$\\\(' )
RULE_DESCS+=('Text("$\\(...") — use Cents (Int) + Decimal.FormatStyle.Currency, not string interpolation of Double')
RULE_EXCLUDES+=('__NONE__')

# 4. TextField without .submitLabel
#    Flag: TextFields that have no .submitLabel in the same closure block.
#    Coarse: file contains TextField( but not .submitLabel
#    (exact per-file done below)

# 5. Inline hex color literals
RULE_IDS+=("INLINE_HEX_COLOR")
RULE_PATTERNS+=('Color(#[0-9a-fA-F]')
RULE_DESCS+=('Inline hex Color(#xxxxxx) — use DesignSystem BrandColors tokens')
RULE_EXCLUDES+=('__NONE__')

# Also catch Color(red: ... green: ... blue: ...) raw inline
RULE_IDS+=("INLINE_RGB_COLOR")
RULE_PATTERNS+=('Color(red: [0-9]')
RULE_DESCS+=('Inline RGB Color(red:green:blue:) — use DesignSystem BrandColors tokens')
RULE_EXCLUDES+=('__NONE__')

# 6. Magic non-token padding values (common offenders: 17, 13, 7, 11, 15, 19, 23)
RULE_IDS+=("MAGIC_PADDING")
RULE_PATTERNS+=('^[^/]*\.padding\((17|13|7|11|15|19|23)\)')
RULE_DESCS+=('.padding(N) with non-token value — use DesignTokens.Spacing.*')
RULE_EXCLUDES+=('__NONE__')

# 7. Missing accessibilityLabel on Image(systemName:) as standalone button/label
#    Coarse: Image(systemName: inside a Button { } without accessibilityLabel on button
RULE_IDS+=("IMAGE_SYSTEM_NO_A11Y")
RULE_PATTERNS+=('Image(systemName:')
RULE_DESCS+=('Image(systemName:) potentially missing accessibilityLabel or accessibilityHidden — verify manually')
RULE_EXCLUDES+=('accessibilityLabel\|accessibilityHidden\|Label(')

# 8. Text("..." + someVariable) string concatenation (should use interpolation)
RULE_IDS+=("TEXT_CONCAT")
RULE_PATTERNS+=('Text("[^"]*" + ')
RULE_DESCS+=('Text("..." + variable) string concatenation — use Text("\\(variable)") interpolation')
RULE_EXCLUDES+=('__NONE__')

# ---------------------------------------------------------------------------
# Special file-level rules (Bash 3.x: no grep -l in a pipeline to arrays)
# ---------------------------------------------------------------------------

echo "================================================================"
echo "UX Polish Lint — §72"
echo "Scanning ${#SWIFT_FILES[@]} Swift files..."
echo "================================================================"

TOTAL_VIOLATIONS=0
REPORT_JSON="[]"

# Helper: append to JSON array
append_json() {
    local rule="$1" file="$2" line_num="$3" line_text="$4"
    # Escape quotes for JSON
    local escaped_text
    escaped_text=$(echo "${line_text}" | sed 's/\\/\\\\/g; s/"/\\"/g')
    local entry
    entry="{\"rule\":\"${rule}\",\"file\":\"${file}\",\"line\":${line_num},\"text\":\"${escaped_text}\"}"
    if [[ "${REPORT_JSON}" == "[]" ]]; then
        REPORT_JSON="[${entry}]"
    else
        REPORT_JSON="${REPORT_JSON%]},${entry}]"
    fi
}

# --- Per-rule grep scan ---
for i in "${!RULE_IDS[@]}"; do
    rule_id="${RULE_IDS[$i]}"
    pattern="${RULE_PATTERNS[$i]}"
    desc="${RULE_DESCS[$i]}"
    exclude="${RULE_EXCLUDES[$i]}"

    rule_count=0
    rule_output=""

    for f in "${SWIFT_FILES[@]}"; do
        if [[ "${exclude}" == "__NONE__" ]]; then
            # Always exclude comment-only lines (/// and //); grep -n output format is "N:content"
            result=$(grep -nE "${pattern}" "${f}" 2>/dev/null | awk -F: '{ rest=substr($0, index($0,$2)); if (rest !~ /^[[:space:]]*\/\//) print }' || true)
        else
            result=$(grep -nE "${pattern}" "${f}" 2>/dev/null | awk -F: '{ rest=substr($0, index($0,$2)); if (rest !~ /^[[:space:]]*\/\//) print }' | grep -vE "${exclude}" || true)
        fi
        # Skip test files for some rules (they may intentionally have raw strings)
        if echo "${f}" | grep -qE '(Tests|Spec|Mock|Preview)'; then
            result=""
        fi
        if [[ -n "${result}" ]]; then
            while IFS= read -r line; do
                line_num=$(echo "${line}" | cut -d: -f1)
                line_text=$(echo "${line}" | cut -d: -f2-)
                rule_output+="${f}:${line}"$'\n'
                append_json "${rule_id}" "${f}" "${line_num}" "${line_text}"
                rule_count=$((rule_count + 1))
            done <<< "${result}"
        fi
    done

    if [[ ${rule_count} -gt 0 ]]; then
        echo ""
        echo "FAIL [${rule_id}] — ${desc}"
        echo "  ${rule_count} violation(s):"
        echo "${rule_output}" | head -10 | while IFS= read -r l; do
            [[ -n "${l}" ]] && echo "    ${l}"
        done
        if [[ ${rule_count} -gt 10 ]]; then
            echo "    ... (${rule_count} total — run with --report for full list)"
        fi
    fi

    TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + rule_count))
done

# --- Special rule: List( without .refreshable in same file ---
LIST_NO_REFRESH_COUNT=0
for f in "${SWIFT_FILES[@]}"; do
    # Skip test files
    echo "${f}" | grep -qE '(Tests|Spec|Mock|Preview)' && continue
    if grep -qE 'List\(' "${f}" 2>/dev/null; then
        if ! grep -qE '\.refreshable' "${f}" 2>/dev/null; then
            echo ""
            echo "FAIL [LIST_NO_REFRESH] — List( found without .refreshable in same file"
            echo "    ${f}"
            append_json "LIST_NO_REFRESH" "${f}" 0 "List( present but no .refreshable found"
            LIST_NO_REFRESH_COUNT=$((LIST_NO_REFRESH_COUNT + 1))
        fi
    fi
done
TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + LIST_NO_REFRESH_COUNT))

# --- Special rule: TextField( without .submitLabel in same file ---
TEXTFIELD_NO_SUBMIT_COUNT=0
for f in "${SWIFT_FILES[@]}"; do
    echo "${f}" | grep -qE '(Tests|Spec|Mock|Preview)' && continue
    if grep -qE 'TextField\(' "${f}" 2>/dev/null; then
        if ! grep -qE '\.submitLabel' "${f}" 2>/dev/null; then
            echo ""
            echo "FAIL [TEXTFIELD_NO_SUBMIT] — TextField( found without .submitLabel in same file"
            echo "    ${f}"
            append_json "TEXTFIELD_NO_SUBMIT" "${f}" 0 "TextField( present but no .submitLabel found"
            TEXTFIELD_NO_SUBMIT_COUNT=$((TEXTFIELD_NO_SUBMIT_COUNT + 1))
        fi
    fi
done
TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + TEXTFIELD_NO_SUBMIT_COUNT))

# ---------------------------------------------------------------------------
echo ""
echo "================================================================"
echo "Total violations: ${TOTAL_VIOLATIONS}  (baseline: ${BASELINE})"
echo "================================================================"

if [[ "${REPORT_MODE}" == "true" ]]; then
    REPORT_PATH="${IOS_ROOT}/ux-polish-lint-report.json"
    printf '{\n  "generated": "%s",\n  "total_violations": %d,\n  "baseline": %d,\n  "violations": %s\n}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "${TOTAL_VIOLATIONS}" \
        "${BASELINE}" \
        "${REPORT_JSON}" \
        > "${REPORT_PATH}"
    echo "JSON report written to ${REPORT_PATH}"
fi

if [[ ${TOTAL_VIOLATIONS} -gt ${BASELINE} ]]; then
    echo "ERROR: ${TOTAL_VIOLATIONS} violation(s) exceed baseline ${BASELINE}." >&2
    echo "Fix anti-patterns or update BASELINE with human sign-off." >&2
    exit 1
fi

echo "OK: within baseline."
exit 0
