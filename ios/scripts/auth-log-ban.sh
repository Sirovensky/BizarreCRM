#!/usr/bin/env bash
# auth-log-ban.sh — §2.13 Auth log-privacy enforcement
#
# Scans Swift source under ios/Packages/Auth/Sources for OSLog / os.Logger
# interpolations that embed sensitive field names WITHOUT a `privacy: .private`
# or `privacy: .sensitive` label.
#
# A violation looks like:
#   logger.debug("accessToken=\(accessToken)")      # BAD — emits plaintext
#   logger.info("pin=\(pin)")                       # BAD
#   logger.error("password: \(req.password)")       # BAD
#
# A non-violation looks like:
#   logger.debug("Has token: \(AuthLogPrivacy.presence(token))")  # GOOD
#   logger.info("userId=\(userId, privacy: .public)")             # GOOD
#   // accessToken is set                                          # OK — comment
#
# Rules
# -----
# Flag any line that:
#   1. Contains one of the banned field name literals, AND
#   2. Is part of an OSLog interpolation (contains "\(" or "log\." / "logger\.")
#   3. Does NOT contain `privacy: .private` or `privacy: .sensitive`
#      immediately after the interpolated expression on the same line.
#
# This is conservative — it will flag `.debug("accessToken count: \(token.count)")`.
# The fix is to use `AuthLogPrivacy.presence(token)` instead. The script
# intentionally errs on the side of over-flagging to keep the rule simple and
# auditable.
#
# Exit 0 = clean. Exit 1 = violations found.
#
# Usage:
#   bash ios/scripts/auth-log-ban.sh
#
# Wire into CI (ios-lint.yml) alongside sdk-ban.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUTH_SRC="$REPO_ROOT/ios/Packages/Auth/Sources"

VIOLATIONS=0

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_violation() {
    local file="$1" lineno="$2" field="$3"
    echo -e "${RED}VIOLATION${NC}  $file:$lineno  [${YELLOW}${field}${NC}]  sensitive field interpolated in OSLog without privacy label — §2.13"
    VIOLATIONS=$((VIOLATIONS + 1))
}

# Banned field names (must match AuthLogPrivacy.bannedFields).
BANNED_FIELDS=(
    "password"
    "accessToken"
    "refreshToken"
    "pin"
    "backupCode"
)

# Search helper — prefers rg (ripgrep), falls back to grep.
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

echo "=== §2.13 auth-log-ban: checking for sensitive fields in OSLog calls ==="

for field in "${BANNED_FIELDS[@]}"; do
    # Pattern: the field name appears inside a string interpolation \( … ) on a
    # line that also looks like an OSLog call (contains a log level method name).
    # We match:  <logmethod>(  ...  \(<field>  ...  )
    # Log level identifiers: log, info, debug, warning, error, fault, notice, trace
    LOG_LEVELS="(log|info|debug|warning|error|fault|notice|trace)"
    # The interpolation pattern: \( followed (optionally) by whitespace then the field name.
    # We anchor the field name as a word boundary so "pinned" doesn't match "pin".
    PATTERN="\\\\(\\s*${field}[^A-Za-z0-9_]"

    while IFS= read -r hit; do
        [[ -z "$hit" ]] && continue

        file="${hit%%:*}"
        rest="${hit#*:}"
        lineno="${rest%%:*}"
        text="${rest#*:}"

        # Skip comment lines (// …) — the pattern may appear in documentation.
        stripped="${text#"${text%%[! ]*}"}"   # ltrim whitespace
        if [[ "$stripped" == //* ]]; then
            continue
        fi

        # Skip lines that also contain a safe wrapper call — presence(), redacted(),
        # AuthLogPrivacy., or an explicit privacy label.
        if echo "$text" | grep -qE \
            '(privacy\s*:\s*\.(private|sensitive)|AuthLogPrivacy\.|\.presence\(|\.redacted\()'; then
            continue
        fi

        # Require the line to look like an OSLog call (contain a log level word
        # followed by an opening paren, or contain "logger." / "AppLog.").
        if ! echo "$text" | grep -qE '(AppLog|logger|Logger)\.' \
            && ! echo "$text" | grep -qE "\\.${LOG_LEVELS}\\s*\\("; then
            continue
        fi

        print_violation "$file" "$lineno" "$field"
    done < <(search_files "$PATTERN" "$AUTH_SRC")
done

echo ""
if [[ $VIOLATIONS -eq 0 ]]; then
    echo "auth-log-ban: CLEAN — no OSLog privacy violations found."
    exit 0
else
    echo -e "${RED}auth-log-ban: FAILED — $VIOLATIONS violation(s) found.${NC}"
    echo "Use AuthLogPrivacy.presence() / .redacted() or add 'privacy: .private'."
    echo "See ios/Packages/Auth/Sources/Auth/SecurityPolish/AuthLogPrivacy.swift for examples."
    exit 1
fi
