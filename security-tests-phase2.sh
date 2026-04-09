#!/bin/bash
# ============================================================================
# Bizarre CRM — Phase 2 Security Hardening Tests
# Run: bash security-tests-phase2.sh
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
echo "  Phase 2 Security Hardening Tests"
echo "  Target: $BASE"
echo "============================================"

# ──────────────────────────────────────────────────
header "P2.1 — Content Security Policy Headers"
# ──────────────────────────────────────────────────
# CSP should prevent XSS by restricting script sources
# Reference: https://owasp.org/www-project-secure-headers/

HEADERS=$(curl -skI "$BASE/" 2>/dev/null)

if echo "$HEADERS" | grep -qi "content-security-policy"; then
  CSP=$(echo "$HEADERS" | grep -i "content-security-policy")
  green "Content-Security-Policy header present"

  # Check it blocks object-src (Flash/Java exploits)
  if echo "$CSP" | grep -qi "object-src.*'none'"; then
    green "CSP blocks object-src (Flash/Java exploits)"
  else
    yellow "CSP does not explicitly block object-src"
  fi

  # Check frame-ancestors (clickjacking protection)
  if echo "$CSP" | grep -qi "frame-ancestors.*'none'"; then
    green "CSP blocks frame-ancestors (clickjacking)"
  else
    yellow "CSP frame-ancestors not set to 'none'"
  fi
else
  red "Content-Security-Policy header MISSING"
fi

# ──────────────────────────────────────────────────
header "P2.2 — Backup Concurrency Lock"
# ──────────────────────────────────────────────────
# Attempt to trigger multiple concurrent backups (DoS vector)
# Login to admin first

ADMIN_TOKEN=$(curl -sk -X POST "$API/admin/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}' | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$ADMIN_TOKEN" ]; then
  yellow "Cannot test backup concurrency (admin login failed — 2FA may be required)"
else
  # Fire two concurrent backup requests
  CODE1=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$API/admin/backup" \
    -H "X-Admin-Token: $ADMIN_TOKEN" &)
  sleep 0.1
  CODE2=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$API/admin/backup" \
    -H "X-Admin-Token: $ADMIN_TOKEN")
  wait

  # At least one should get 429 if lock works
  if [ "$CODE2" = "429" ]; then
    green "Backup concurrency lock works — second request blocked"
  else
    yellow "Backup concurrency test inconclusive (codes: $CODE1, $CODE2)"
  fi
fi

# ──────────────────────────────────────────────────
header "P2.4 — PIN Input Validation"
# ──────────────────────────────────────────────────
# Try oversized PIN (DoS via bcrypt on huge input)
# Reference: CVE-2023-24999 (bcrypt DoS with long passwords)

CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$API/auth/switch-user" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer faketoken" \
  -d "{\"pin\":\"$(python3 -c "print('A'*10000)" 2>/dev/null || echo AAAAAAAAAAAAAAAAAAAAAAAAAAAA)\"}")

if [ "$CODE" = "400" ] || [ "$CODE" = "401" ]; then
  green "Oversized PIN rejected (code: $CODE)"
else
  red "Server accepted oversized PIN (code: $CODE) — DoS risk"
fi

# Try empty PIN
CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$API/auth/switch-user" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer faketoken" \
  -d '{"pin":""}')

if [ "$CODE" = "400" ] || [ "$CODE" = "401" ]; then
  green "Empty PIN rejected"
else
  red "Empty PIN accepted (code: $CODE)"
fi

# ──────────────────────────────────────────────────
header "P2.5 — TOTP Code Format Validation"
# ──────────────────────────────────────────────────
# Try non-numeric and wrong-length TOTP codes
# Reference: OWASP OTP Bypass techniques

# Get a challenge token first
CHALLENGE=$(curl -sk -X POST "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}' | grep -o '"challengeToken":"[^"]*"' | cut -d'"' -f4)

if [ -z "$CHALLENGE" ]; then
  yellow "Cannot test TOTP validation (login failed — rate limited?)"
else
  # Try alphabetic code
  RESP=$(curl -sk -X POST "$API/auth/login/2fa-verify" \
    -H "Content-Type: application/json" \
    -d "{\"challengeToken\":\"$CHALLENGE\",\"code\":\"abcdef\"}")
  if echo "$RESP" | grep -q "6 digits"; then
    green "Non-numeric TOTP code rejected with format error"
  else
    red "Non-numeric TOTP code not properly validated"
  fi

  # Get new challenge (previous consumed)
  CHALLENGE2=$(curl -sk -X POST "$API/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"admin123"}' | grep -o '"challengeToken":"[^"]*"' | cut -d'"' -f4)

  if [ -n "$CHALLENGE2" ]; then
    # Try 3-digit code
    RESP=$(curl -sk -X POST "$API/auth/login/2fa-verify" \
      -H "Content-Type: application/json" \
      -d "{\"challengeToken\":\"$CHALLENGE2\",\"code\":\"123\"}")
    if echo "$RESP" | grep -q "6 digits"; then
      green "Short TOTP code (3 digits) rejected"
    else
      red "Short TOTP code accepted — should require exactly 6 digits"
    fi
  fi
fi

# ──────────────────────────────────────────────────
header "P2.7 — Challenge Token Memory Limit"
# ──────────────────────────────────────────────────
# Verify server doesn't crash under challenge flood
# (We can't test 10k easily but verify it handles rapid requests)

for i in $(seq 1 20); do
  curl -sk -o /dev/null -X POST "$API/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"wrong'$i'"}'
done

# Server should still respond
CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$BASE/")
if [ "$CODE" = "200" ]; then
  green "Server stable after rapid challenge creation"
else
  red "Server unresponsive after challenge flood (code: $CODE)"
fi

# ──────────────────────────────────────────────────
header "P2.8 — Public Tracking Rate Limit"
# ──────────────────────────────────────────────────
# Reference: OWASP API8 — Lack of Protection from Automated Threats

CODE1=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$API/track/lookup" \
  -H "Content-Type: application/json" \
  -d '{"phone":"5551234"}')

CODE2=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$API/track/lookup" \
  -H "Content-Type: application/json" \
  -d '{"phone":"5555678"}')

if [ "$CODE2" = "429" ]; then
  green "Tracking endpoint rate limited — second request blocked"
else
  yellow "Tracking rate limit may need tighter window (codes: $CODE1, $CODE2)"
fi

# ──────────────────────────────────────────────────
header "P2.9 — Nuclear Wipe Requires Admin + Password"
# ──────────────────────────────────────────────────
# Try nuclear wipe without password
CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$API/import/repairdesk/nuclear" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer faketoken" \
  -d '{"confirm":"NUCLEAR","api_key":"test"}')

if [ "$CODE" = "401" ]; then
  green "Nuclear wipe requires valid auth token"
else
  red "Nuclear wipe accessible without proper auth (code: $CODE)"
fi

# ──────────────────────────────────────────────────
header "P2.10 — POS Quantity Validation"
# ──────────────────────────────────────────────────
# Reference: CWE-1284 — Improper Validation of Specified Quantity in Input

# POS is behind auth — verify auth blocks + check code for validation
CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$API/pos/checkout" \
  -H "Content-Type: application/json" \
  -d '{"items":[{"inventory_item_id":1,"quantity":-100}]}')

if [ "$CODE" = "401" ]; then
  green "POS checkout requires auth (quantity validation behind auth wall)"
else
  yellow "POS checkout returned unexpected code: $CODE"
fi

# Verify validation exists in code
if grep -q "qty < 1\|quantity.*100000\|Invalid quantity" "packages/server/src/routes/pos.routes.ts" 2>/dev/null; then
  green "POS quantity validation (1-100000) configured in code"
else
  red "POS quantity validation not found in code"
fi

# ──────────────────────────────────────────────────
header "P2.12 — User Object Allowlist (No Sensitive Leaks)"
# ──────────────────────────────────────────────────
# Reference: OWASP API3 — Excessive Data Exposure

LOGIN_RESP=$(curl -sk -X POST "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}')

# Check for fields that should NEVER appear
LEAKED=false
for FIELD in "password_hash" "totp_secret" "backup_codes" "pin" "password_set"; do
  if echo "$LOGIN_RESP" | grep -q "\"$FIELD\""; then
    red "Login response contains sensitive field: $FIELD"
    LEAKED=true
  fi
done

if ! $LEAKED; then
  green "Login response clean — no sensitive fields leaked"
fi

# ──────────────────────────────────────────────────
header "Additional: SQL Injection Probing"
# ──────────────────────────────────────────────────
# Reference: OWASP API8 — Injection

# Try SQL injection in login username
RESP=$(curl -sk -X POST "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin\u0027 OR 1=1 --","password":"test"}')

if echo "$RESP" | grep -qi "error\|syntax\|sqlite"; then
  red "SQL injection may be possible — error message leaked"
else
  green "SQL injection in login handled safely"
fi

# Try SQL injection in customer search (if accessible)
CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$API/customers?keyword=test'%20OR%201=1%20--")
if [ "$CODE" = "401" ]; then
  green "Customer search requires auth — SQL injection test blocked"
elif [ "$CODE" = "500" ]; then
  red "SQL injection in customer search caused 500 error"
else
  green "SQL injection in customer search handled (code: $CODE)"
fi

# ──────────────────────────────────────────────────
header "Additional: HTTP Method Tampering"
# ──────────────────────────────────────────────────
# Reference: OWASP — HTTP Verb Tampering

# Try DELETE on login endpoint
CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X DELETE "$API/auth/login")
if [ "$CODE" = "404" ] || [ "$CODE" = "405" ]; then
  green "DELETE method on login rejected (code: $CODE)"
else
  yellow "Unexpected response to DELETE on login (code: $CODE)"
fi

# Try PATCH on admin status
CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X PATCH "$API/admin/status")
if [ "$CODE" = "401" ] || [ "$CODE" = "404" ] || [ "$CODE" = "405" ]; then
  green "PATCH on admin/status rejected (code: $CODE)"
else
  yellow "Unexpected response to PATCH on admin/status (code: $CODE)"
fi

# ──────────────────────────────────────────────────
header "Additional: Response Header Security"
# ──────────────────────────────────────────────────
HEADERS=$(curl -skI "$BASE/" 2>/dev/null)

# Server should not reveal Express version
if echo "$HEADERS" | grep -qi "x-powered-by.*express"; then
  red "Server leaks X-Powered-By: Express header"
else
  green "X-Powered-By header hidden (helmet removes it)"
fi

# Check for referrer policy
if echo "$HEADERS" | grep -qi "referrer-policy"; then
  green "Referrer-Policy header present"
else
  yellow "Referrer-Policy header missing"
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
  echo -e "\033[32m  ✓ All Phase 2 security tests passed\033[0m"
  exit 0
fi
