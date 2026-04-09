#!/bin/bash
# ============================================================================
# Bizarre CRM — Phase 3 Defense in Depth Tests
# Run: bash security-tests-phase3.sh
# ============================================================================

BASE="https://localhost:443"
API="$BASE/api/v1"
PASS=0
FAIL=0
WARN=0

red()   { echo -e "\033[31m  FAIL: $1\033[0m"; FAIL=$((FAIL+1)); }
green() { echo -e "\033[32m  PASS: $1\033[0m"; PASS=$((PASS+1)); }
yellow(){ echo -e "\033[33m  WARN: $1\033[0m"; WARN=$((WARN+1)); }
header(){ echo -e "\n\033[1;36m[$1]\033[0m"; }

echo "============================================"
echo "  Phase 3 Defense in Depth Tests"
echo "  Target: $BASE"
echo "============================================"

# ──────────────────────────────────────────────────
header "P3.1 — Audit Logging"
# ──────────────────────────────────────────────────
# Reference: OWASP A09 — Security Logging and Monitoring Failures

# Trigger a failed login to generate an audit log entry
curl -sk -o /dev/null -X POST "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"audit_test_user","password":"wrong"}'

# Check audit_logs table exists and has entries (via code check)
if grep -rq "audit_logs" "packages/server/src/db/migrations/" 2>/dev/null; then
  green "Audit logs table exists in migrations"
else
  red "Audit logs table missing"
fi

if grep -rq "audit(" "packages/server/src/routes/auth.routes.ts" 2>/dev/null; then
  green "Auth routes have audit logging calls"
else
  red "Auth routes missing audit logging"
fi

if grep -rq "audit(" "packages/server/src/routes/admin.routes.ts" 2>/dev/null; then
  green "Admin routes have audit logging calls"
else
  red "Admin routes missing audit logging"
fi

# ──────────────────────────────────────────────────
header "P3.2 — Encryption Key Versioning"
# ──────────────────────────────────────────────────
# Reference: NIST SP 800-57 — Key Management

if grep -q "ENCRYPTION_KEYS.*Record\|CURRENT_KEY_VERSION" "packages/server/src/routes/auth.routes.ts" 2>/dev/null; then
  green "TOTP encryption uses versioned keys"
else
  red "TOTP encryption has no key versioning"
fi

# Check that new encryptions include version prefix
if grep -q "v\${CURRENT_KEY_VERSION}" "packages/server/src/routes/auth.routes.ts" 2>/dev/null; then
  green "Encrypted secrets include version prefix"
else
  red "Encrypted secrets missing version prefix"
fi

# Check backwards compat with legacy format
if grep -q "Legacy.*unencrypted\|Legacy.*v0" "packages/server/src/routes/auth.routes.ts" 2>/dev/null; then
  green "Decryption supports legacy formats (migration safe)"
else
  yellow "No legacy format support in decryption"
fi

# ──────────────────────────────────────────────────
header "P3.3 — SMS Send Rate Limit"
# ──────────────────────────────────────────────────
# Reference: OWASP API4 — Unrestricted Resource Consumption

if grep -q "smsSendLimiter\|SMS rate limit" "packages/server/src/routes/sms.routes.ts" 2>/dev/null; then
  green "SMS send endpoint has rate limiting"
else
  red "SMS send endpoint has no rate limiting — cost abuse possible"
fi

# Verify rate limit is per-user (not just global)
if grep -q "userId.*smsSendLimiter\|smsSendLimiter.*get.*userId" "packages/server/src/routes/sms.routes.ts" 2>/dev/null; then
  green "SMS rate limit is per-user (not bypassable by multiple users)"
else
  yellow "SMS rate limit may not be per-user"
fi

# ──────────────────────────────────────────────────
header "P3.4 — CORS Configuration"
# ──────────────────────────────────────────────────
# Reference: MDN CORS, OWASP CORS misconfigurations

# Test from evil origin
RESP=$(curl -skI -H "Origin: https://evil-phishing-site.com" "$API/auth/login" 2>/dev/null)
if echo "$RESP" | grep -qi "access-control-allow-origin.*evil"; then
  red "CORS reflects evil origin — vulnerable to cross-origin attacks"
else
  green "CORS rejects evil origins"
fi

# Test from LAN IP (should be allowed)
RESP=$(curl -skI -H "Origin: http://192.168.1.100:443" "$API/auth/login" 2>/dev/null)
if echo "$RESP" | grep -qi "access-control-allow-origin"; then
  green "CORS allows LAN origins (expected for repair shop network)"
else
  yellow "CORS may block LAN origins (check if intended)"
fi

# Test null origin attack (can be spoofed via sandboxed iframes)
RESP=$(curl -skI -H "Origin: null" "$API/auth/login" 2>/dev/null)
if echo "$RESP" | grep -qi "access-control-allow-origin.*null"; then
  red "CORS allows null origin — vulnerable to sandboxed iframe attacks"
else
  green "CORS rejects null origin"
fi

# ──────────────────────────────────────────────────
header "P3.5 — HTTPS Enforcement"
# ──────────────────────────────────────────────────
# Reference: OWASP Transport Layer Protection

if grep -q "x-forwarded-proto.*https\|HTTPS redirect" "packages/server/src/index.ts" 2>/dev/null; then
  green "HTTPS redirect configured for production"
else
  red "No HTTPS redirect — all traffic sent in cleartext"
fi

# Check HSTS header present
HEADERS=$(curl -skI "$BASE/" 2>/dev/null)
if echo "$HEADERS" | grep -qi "strict-transport-security"; then
  green "HSTS header present (enforces HTTPS in browsers)"
else
  red "HSTS header missing"
fi

# ──────────────────────────────────────────────────
header "P3.6 — Webhook Signature Verification"
# ──────────────────────────────────────────────────
# Reference: Twilio webhook security, OWASP API10

if grep -q "verifyWebhookSignature" "packages/server/src/routes/sms.routes.ts" 2>/dev/null; then
  green "Webhook signature verification hook in place"
else
  red "No webhook signature verification"
fi

# Try sending a fake webhook — should not crash
CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$API/sms/inbound-webhook" \
  -H "Content-Type: application/json" \
  -d '{"from":"+15551234567","body":"fake message"}')
if [ "$CODE" = "200" ] || [ "$CODE" = "403" ]; then
  green "Webhook endpoint handles requests without crashing (code: $CODE)"
else
  yellow "Webhook endpoint returned unexpected code: $CODE"
fi

# ──────────────────────────────────────────────────
header "Additional: Full Header Security Audit"
# ──────────────────────────────────────────────────
# Reference: securityheaders.com, OWASP Secure Headers Project

HEADERS=$(curl -skI "$BASE/" 2>/dev/null)

check_header() {
  if echo "$HEADERS" | grep -qi "$1"; then
    green "Header: $1"
  else
    red "MISSING: $1"
  fi
}

check_header "X-Content-Type-Options"
check_header "X-Frame-Options"
check_header "Content-Security-Policy"
check_header "Strict-Transport-Security"
check_header "Referrer-Policy"
check_header "X-DNS-Prefetch-Control"

# Verify no server version leaked
if echo "$HEADERS" | grep -qi "x-powered-by"; then
  red "X-Powered-By header leaks server info"
else
  green "X-Powered-By hidden"
fi

if echo "$HEADERS" | grep -qi "server:.*express\|server:.*node"; then
  red "Server header leaks technology stack"
else
  green "Server header clean"
fi

# ──────────────────────────────────────────────────
header "Additional: Cookie Security Flags"
# ──────────────────────────────────────────────────
# Reference: OWASP Session Management, RFC 6265bis

# Trigger a login to get Set-Cookie header
LOGIN_RESP=$(curl -skI -X POST "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}')

# Check if any cookies are set with proper flags
if echo "$LOGIN_RESP" | grep -qi "set-cookie.*httponly"; then
  green "Cookies use HttpOnly flag"
elif echo "$LOGIN_RESP" | grep -qi "set-cookie"; then
  red "Cookies present but missing HttpOnly flag"
else
  green "No cookies set at login step (tokens via challenge flow)"
fi

# ============================================
echo ""
echo "============================================"
echo -e "  Results: \033[32m$PASS passed\033[0m, \033[31m$FAIL failed\033[0m, \033[33m$WARN warnings\033[0m"
echo "============================================"

if [ $FAIL -gt 0 ]; then
  echo -e "\033[31m  ⚠ SECURITY ISSUES FOUND — Review failures above\033[0m"
  exit 1
else
  echo -e "\033[32m  ✓ All Phase 3 defense-in-depth tests passed\033[0m"
  exit 0
fi
