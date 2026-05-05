#!/usr/bin/env bash
# i18n-audit.sh — §27 hardcoded-string audit
#
# Greps Swift source in ios/ for hardcoded English-looking string literals that
# appear in SwiftUI call sites (Text, Button, .navigationTitle, Label, etc.)
# but are NOT wrapped in L10n.* or NSLocalizedString(...)
#
# Exits 0  when violations are at or below BASELINE (tracked regression).
# Exits 1  when violations EXCEED BASELINE (regression alert).
#
# Usage:
#   bash ios/scripts/i18n-audit.sh           # normal run
#   bash ios/scripts/i18n-audit.sh --report  # also write ios/i18n-audit-report.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Allowed violation baseline — represents existing hardcoded strings in the
# codebase at the time §27 scaffold landed.  Track this number DOWN over time;
# never let it go UP without a deliberate human decision.
BASELINE=50

REPORT_MODE=false
if [[ "${1:-}" == "--report" ]]; then
    REPORT_MODE=true
fi

# ---------------------------------------------------------------------------
# Patterns to flag:
#   Text("...any English-looking content...")
#   Button("...")
#   .navigationTitle("...")
#   Label("...")
#   .toolbar { ToolbarItem { ... Text("...") } }  — covered by Text pattern
# Exclusions:
#   L10n.  — already localised
#   NSLocalizedString — already localised
#   String(localized: — already localised
#   // — comment lines
#   #Preview — preview code (acceptable)
#   "" — empty string
#   pure identifiers / file names / system names (no spaces, short)
# ---------------------------------------------------------------------------

SWIFT_SRC_DIRS=(
    "${IOS_ROOT}/App"
    "${IOS_ROOT}/Packages"
    "${IOS_ROOT}/BizarreCRMWidgets"
)

# Collect all Swift files, excluding .build and test helpers
SWIFT_FILES=()
for dir in "${SWIFT_SRC_DIRS[@]}"; do
    if [[ -d "${dir}" ]]; then
        while IFS= read -r -d '' f; do
            SWIFT_FILES+=("${f}")
        done < <(find "${dir}" -name "*.swift" \
                     -not -path "*/.build/*" \
                     -not -path "*/checkouts/*" \
                     -print0)
    fi
done

if [[ ${#SWIFT_FILES[@]} -eq 0 ]]; then
    echo "WARNING: No Swift source files found under ${IOS_ROOT}" >&2
    exit 0
fi

# Run grep across all files; capture output for counting
VIOLATIONS=""

for pattern in \
    'Text("[A-Z][a-zA-Z ]{2,}"' \
    'Button("[A-Z][a-zA-Z ]{2,}"' \
    '\.navigationTitle("[A-Z][a-zA-Z ]{2,}"' \
    'Label("[A-Z][a-zA-Z ]{2,}"' \
    '\.placeholder\("[A-Z][a-zA-Z ]{2,}"' \
    '\.alert("[A-Z][a-zA-Z ]{2,}"' \
    '\.confirmationDialog("[A-Z][a-zA-Z ]{2,}"'
do
    for f in "${SWIFT_FILES[@]}"; do
        result=$(grep -nE "${pattern}" "${f}" 2>/dev/null | \
                 grep -vE '(L10n\.|NSLocalizedString|String\(localized|#Preview|//|\.accessibilityLabel|A11yLabel)' || true)
        if [[ -n "${result}" ]]; then
            while IFS= read -r line; do
                VIOLATIONS+="${f}:${line}"$'\n'
            done <<< "${result}"
        fi
    done
done

# Deduplicate (same line may match multiple patterns)
if [[ -n "${VIOLATIONS}" ]]; then
    VIOLATIONS=$(echo "${VIOLATIONS}" | sort -u)
fi

VIOLATION_COUNT=$(echo "${VIOLATIONS}" | grep -c . 2>/dev/null || echo 0)
if [[ -z "${VIOLATIONS}" ]]; then
    VIOLATION_COUNT=0
fi

echo "i18n audit: ${VIOLATION_COUNT} hardcoded-string violations found (baseline: ${BASELINE})"

if [[ "${REPORT_MODE}" == "true" ]]; then
    REPORT_PATH="${IOS_ROOT}/i18n-audit-report.txt"
    {
        echo "# i18n Hardcoded String Audit Report"
        echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "# Violations: ${VIOLATION_COUNT} / baseline: ${BASELINE}"
        echo ""
        if [[ -n "${VIOLATIONS}" ]]; then
            echo "${VIOLATIONS}"
        else
            echo "(no violations)"
        fi
    } > "${REPORT_PATH}"
    echo "Report written to ${REPORT_PATH}"
fi

if [[ ${VIOLATION_COUNT} -gt ${BASELINE} ]]; then
    echo "ERROR: violation count (${VIOLATION_COUNT}) exceeds baseline (${BASELINE})." >&2
    echo "Fix hardcoded strings or update BASELINE with human sign-off." >&2
    if [[ -n "${VIOLATIONS}" ]]; then
        echo ""
        echo "--- First 20 violations ---"
        echo "${VIOLATIONS}" | head -20
    fi
    exit 1
fi

echo "OK: within baseline."
exit 0
