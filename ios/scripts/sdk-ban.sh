#!/usr/bin/env bash
# sdk-ban.sh — Phase 0 / §32 data-sovereignty lint
#
# Blocks forbidden third-party SDK imports, bare URLSession usage outside the
# approved networking location, and APIClient method calls outside repository
# files. Run by CI (ios-lint.yml) and locally before push.
#
# Exit 0 = clean. Exit 1 = violation(s) found.
#
# Usage:
#   bash ios/scripts/sdk-ban.sh
#   bash ios/scripts/sdk-ban.sh --dry-run   (same — always non-destructive)
#
# See ios/ActionPlan.md §32 and agent-ownership.md Phase 0 gate for rationale.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_ROOT="$REPO_ROOT/ios"

VIOLATIONS=0
TOTAL_FILES=0

# ── Helpers ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_violation() {
    local file="$1" lineno="$2" matched="$3" reason="$4"
    echo -e "${RED}VIOLATION${NC}  $file:$lineno  [${YELLOW}${matched}${NC}]  ${reason}"
    VIOLATIONS=$((VIOLATIONS + 1))
}

# Search with ripgrep if available, fall back to grep -rn.
# $1 = pattern, $2 = directory
# Outputs lines in format:  filepath:lineno:text
# Excludes .build/ directories (SPM build artifacts / resolved package checkouts).
search_files() {
    local pattern="$1" dir="$2"
    if command -v rg &>/dev/null; then
        rg --no-heading -n --type swift \
            --glob '!**/.build/**' \
            --glob '!**/DerivedData/**' \
            "$pattern" "$dir" 2>/dev/null || true
    else
        grep -rn --include="*.swift" \
            --exclude-dir='.build' \
            --exclude-dir='DerivedData' \
            -E "$pattern" "$dir" 2>/dev/null || true
    fi
}

# ── 1. Forbidden third-party SDK imports ─────────────────────────────────────
# §32 / agent-ownership.md: "No third-party SDK may open a network socket."
# The import statement is the canonical signal; we match `import <SDK>` or
# `@_implementationOnly import <SDK>` at the start of a (trimmed) line.
# False positives inside // comments are acceptable — reviewer resolves.

BANNED_SDKS=(
    "Firebase"
    "Crashlytics"
    "Mixpanel"
    "Amplitude"
    "Segment"
    "Intercom"
    "Sentry"
    "DataDog"
    "Datadog"
    "Stripe"
    "AppsFlyer"
    "Bugsnag"
    "NewRelic"
    "GoogleAnalytics"
)

echo "=== §32 SDK ban: checking for forbidden third-party SDK imports ==="
for sdk in "${BANNED_SDKS[@]}"; do
    # Match `import <Sdk>` or `import <Sdk>.Something` (case-sensitive).
    # The word boundary after the SDK name avoids false-positives like
    # `import FirebaseMessaging` when only `Firebase` is banned — but we ban
    # both anyway so this is belt-and-suspenders.
    pattern="^[[:space:]]*(@_implementationOnly[[:space:]]+)?import[[:space:]]+${sdk}"
    while IFS= read -r hit; do
        [[ -z "$hit" ]] && continue
        file="${hit%%:*}"
        rest="${hit#*:}"
        lineno="${rest%%:*}"
        text="${rest#*:}"
        print_violation "$file" "$lineno" "$sdk" "forbidden SDK import — §32 data sovereignty"
    done < <(search_files "$pattern" "$IOS_ROOT")
done

# ── 2. Bare URLSession outside approved networking location ───────────────────
# §28.3 / agent-ownership.md Phase 0 gate:
#   URLSession(...) construction is only allowed inside:
#     ios/Packages/Networking/Sources/Networking/
#   URLSession.shared is also permitted there only — but since .shared usage
#   without configuration is common in Apple sample code, we only ban
#   URLSession(configuration:...) and URLSession(configuration:delegate:...)
#   constructor calls outside the approved path.
#
# The approved paths:
URLSESSION_WHITELIST=(
    "ios/Packages/Networking/Sources/Networking/"
    "ios/Packages/Core/Sources/Core/Networking/"
)

echo ""
echo "=== §28.3 URLSession containment: checking for bare URLSession construction ==="

# Pattern: URLSession( — covers URLSession(configuration:), URLSession(configuration:delegate:...).
# We do NOT flag URLSession.shared since it appears in many framework wrappers;
# the ban is on raw constructor calls that bypass our pinning/config layer.
URLSESSION_PATTERN="URLSession\("

while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    file="${hit%%:*}"
    rest="${hit#*:}"
    lineno="${rest%%:*}"
    text="${rest#*:}"

    # Skip files in the whitelist.
    whitelisted=false
    for wl in "${URLSESSION_WHITELIST[@]}"; do
        if [[ "$file" == *"$wl"* ]]; then
            whitelisted=true
            break
        fi
    done
    $whitelisted && continue

    print_violation "$file" "$lineno" "URLSession(" \
        "bare URLSession construction outside approved networking path — §28.3"
done < <(search_files "$URLSESSION_PATTERN" "$IOS_ROOT")

# ── 3. APIClient method calls outside *Repository.swift or *Endpoints.swift ───
# agent-ownership.md Phase 0 gate:
#   APIClient.{get,post,patch,put,delete} called from outside a *Repository file
#   or *Endpoints.swift file is a containment violation.
#
# Detection strategy: look for the patterns that uniquely identify an
# APIClient call versus other Swift method calls with the same name:
#   - `await api.get("`     — api variable calling get/post/etc with a path literal
#   - `await api.post("`    — same for post
#   - `await client.get("`  — alternate variable name
#   - `await self.api.get(` — property access
#
# We require ALL of:
#   1. `await` keyword on the same line (API calls are async; ViewModel/repo
#      internal calls may not be)
#   2. Followed by an identifier + .get/post/patch/put/delete + ( + quote
#      (string path argument is the distinguishing marker — "/api/..." path)
#
# This deliberately avoids false-positives like:
#   - vm.delete(template:)        — no await + path string
#   - NotificationCenter.post(    — no path string
#   - keychain.get(key:)          — no path string
#   - repository.delete(role:)    — no await + string path
#
# Approved zones (no violation emitted):
#   - *Repository.swift, *Endpoints.swift, *Flow.swift (auth bootstrap)
#   - Auth package (session layer — legitimate direct API calls pre-repository)
#   - Networking package sources / tests
#   - APIClient.swift, APIClient+*.swift

# Pattern: await <ident>.(get|post|patch|put|delete)(" — the string path literal
# is the key discriminator. Non-networking calls pass a non-string first arg.
APICLIENT_PATTERN='await\s+\w+(\.\w+)*\.(get|post|patch|put|delete)\s*\(\s*"'

echo ""
echo "=== §20 APIClient containment: checking for calls outside *Repository/*Endpoints ==="

while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    file="${hit%%:*}"
    rest="${hit#*:}"
    lineno="${rest%%:*}"
    text="${rest#*:}"

    # Basename of the file (without directory).
    basename="${file##*/}"

    # Approved files / packages — no violation.
    if [[ "$basename" == *"Repository.swift" ]] \
        || [[ "$basename" == *"Endpoints.swift" ]] \
        || [[ "$basename" == "APIClient.swift" ]] \
        || [[ "$basename" == "APIClient+"* ]] \
        || [[ "$basename" == "AppServices.swift" ]] \
        || [[ "$file" == *"Auth/Sources/"* ]] \
        || [[ "$file" == *"Networking/Sources/Networking/"* ]] \
        || [[ "$file" == *"Networking/Tests/"* ]] \
        || [[ "$file" == *"/Tests/"* ]]; then
        continue
    fi

    # Extract the method name for reporting.
    method=$(echo "$text" | grep -oE '\.(get|post|patch|put|delete)\s*\(' | head -1 | tr -d ' ')
    print_violation "$file" "$lineno" "${method}" \
        "APIClient method called outside *Repository/*Endpoints — §20 containment"
done < <(search_files "$APICLIENT_PATTERN" "$IOS_ROOT")

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
if [[ $VIOLATIONS -eq 0 ]]; then
    echo "sdk-ban: CLEAN — no violations found."
    exit 0
else
    echo -e "${RED}sdk-ban: FAILED — $VIOLATIONS violation(s) found.${NC}"
    echo "Fix violations before merging. See ios/ActionPlan.md §32 for policy."
    exit 1
fi
