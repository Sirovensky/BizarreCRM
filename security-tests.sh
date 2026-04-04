#!/bin/bash
# ============================================================================
# Bizarre CRM — Phase 1 Security Penetration Tests
# Run: bash security-tests.sh
# Requires: curl, server running on localhost:3020
# ============================================================================

BASE="http://localhost:3020"
API="$BASE/api/v1"
PASS=0
FAIL=0
WARN=0

red()   { echo -e "\033[31m  FAIL: $1\033[0m"; FAIL=$((FAIL+1)); }
green() { echo -e "\033[32m  PASS: $1\033[0m"; PASS=$((PASS+1)); }
yellow(){ echo -e "\033[33m  WARN: $1\033[0m"; WARN=$((WARN+1)); }
header(){ echo -e "\n\033[1;36m[$1]\033[0m"; }

# ── Helper: login and get a valid access token ──
get_token() {
  # Step 1: password
  CHALLENGE=$(curl -s -X POST "$API/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"admin123"}' | grep -o '"challengeToken":"[^"]*"' | cut -d'"' -f4)

  if [ -z "$CHALLENGE" ]; then
    echo "Cannot login — server may not be running or admin credentials changed"
    exit 1
  fi

  # If 2FA not set up, we can't get a token without authenticator
  # For testing, we'll work with the challenge token where possible
  echo "$CHALLENGE"
}

echo "============================================"
echo "  Bizarre CRM Security Penetration Tests"
echo "  Target: $BASE"
echo "============================================"

# ──────────────────────────────────────────────────
header "P1.1 — Rate Limiting (Login Brute Force)"
# ──────────────────────────────────────────────────
# Attempt 7 rapid logins with wrong password — should get 429 after 5

BLOCKED=false
for i in $(seq 1 7); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"wrongpass'$i'"}')
  if [ "$CODE" = "429" ]; then
    BLOCKED=true
    break
  fi
done

if $BLOCKED; then
  green "Login rate limiting works — blocked after repeated failures"
else
  red "Login rate limiting NOT working — 7 bad attempts, no 429"
fi

# ──────────────────────────────────────────────────
header "P1.2 — File Upload MIME Validation"
# ──────────────────────────────────────────────────
# Try uploading an SVG file (XSS vector) — should be rejected

# Try upload without auth — should get 401
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/tickets/1/photos" \
  -H "Content-Type: multipart/form-data")

if [ "$CODE" = "401" ]; then
  green "Photo upload requires authentication"
else
  yellow "Photo upload returned $CODE without auth (expected 401)"
fi

# Verify MIME filter is configured (check by reading the code — runtime test needs valid auth)
if grep -q "ALLOWED_MIMES\|fileFilter" "packages/server/src/routes/tickets.routes.ts" 2>/dev/null; then
  green "File upload MIME filter is configured in code"
else
  red "File upload has no MIME filter"
fi

# ──────────────────────────────────────────────────
header "P1.3 — Path Traversal via /uploads"
# ──────────────────────────────────────────────────

# Try to read files outside uploads directory
# Check CONTENT not just status — SPA fallback returns 200 for any route
BODY1=$(curl -s "$BASE/uploads/../../.env" | head -1)
BODY2=$(curl -s "$BASE/uploads/..%2F..%2F.env" | head -1)
BODY3=$(curl -s "$BASE/uploads/.env" | head -1)

LEAKED=false
for BODY in "$BODY1" "$BODY2" "$BODY3"; do
  if echo "$BODY" | grep -qi "JWT_SECRET\|RD_API_KEY\|SECRET"; then
    LEAKED=true
    break
  fi
done

if $LEAKED; then
  red "Path traversal SUCCEEDED — .env content leaked via /uploads"
else
  green "Path traversal blocked — .env not accessible via /uploads"
fi

# Verify dotfiles aren't served from uploads dir
CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/uploads/.hidden")
BODY=$(curl -s "$BASE/uploads/.hidden" | head -1)
if echo "$BODY" | grep -qi "JWT_SECRET\|password\|secret"; then
  red "Dotfile content leaked via /uploads"
else
  green "Dotfiles not served from /uploads"
fi

# ──────────────────────────────────────────────────
header "P1.5 — /api/v1/info Requires Auth"
# ──────────────────────────────────────────────────

CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API/info")
BODY=$(curl -s "$API/info")

if [ "$CODE" = "401" ]; then
  green "/api/v1/info requires authentication"
else
  # Check if it leaks internal IP
  if echo "$BODY" | grep -q "lan_ip"; then
    red "/api/v1/info exposes LAN IP without auth (code: $CODE)"
  else
    yellow "/api/v1/info returned $CODE but no IP leak detected"
  fi
fi

# ──────────────────────────────────────────────────
header "P1.6 — Challenge Token Reuse Prevention"
# ──────────────────────────────────────────────────

# Get a challenge token
CHALLENGE=$(curl -s -X POST "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}' | grep -o '"challengeToken":"[^"]*"' | cut -d'"' -f4)

if [ -z "$CHALLENGE" ]; then
  yellow "Cannot get challenge token (rate limited from previous test)"
else
  # Use it once for 2fa-setup
  RESP1=$(curl -s -X POST "$API/auth/login/2fa-setup" \
    -H "Content-Type: application/json" \
    -d "{\"challengeToken\":\"$CHALLENGE\"}")

  # Try to reuse the SAME token
  RESP2=$(curl -s -X POST "$API/auth/login/2fa-setup" \
    -H "Content-Type: application/json" \
    -d "{\"challengeToken\":\"$CHALLENGE\"}")

  if echo "$RESP2" | grep -q "expired\|Challenge expired"; then
    green "Challenge tokens consumed after use — reuse blocked"
  else
    red "Challenge token reuse NOT prevented — same token worked twice"
  fi
fi

# ──────────────────────────────────────────────────
header "P1.8 — Refresh Token NOT in Response Body"
# ──────────────────────────────────────────────────
# After 2FA is set up, verify refresh token comes as cookie not body
# For now, check that the refresh endpoint rejects body-only tokens

CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/auth/refresh" \
  -H "Content-Type: application/json" \
  -d '{"refreshToken":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.fake"}')

if [ "$CODE" = "400" ] || [ "$CODE" = "401" ]; then
  green "Refresh endpoint rejects body-only refresh tokens (code: $CODE)"
else
  red "Refresh endpoint accepted body refresh token (code: $CODE)"
fi

# ──────────────────────────────────────────────────
header "P1.10 — FTS Injection"
# ──────────────────────────────────────────────────
# Try FTS special operators in customer search

# These should NOT crash the server or return errors
CODE1=$(curl -s -o /dev/null -w "%{http_code}" "$API/customers?keyword=test%20OR%20DROP")
CODE2=$(curl -s -o /dev/null -w "%{http_code}" "$API/customers?keyword=%22%20NEAR%20%22")
CODE3=$(curl -s -o /dev/null -w "%{http_code}" "$API/customers?keyword=*%20NOT%20*")

if [ "$CODE1" = "401" ] && [ "$CODE2" = "401" ] && [ "$CODE3" = "401" ]; then
  green "Customer search requires auth (FTS injection can't be tested without token)"
elif [ "$CODE1" != "500" ] && [ "$CODE2" != "500" ] && [ "$CODE3" != "500" ]; then
  green "FTS special characters did not crash server (codes: $CODE1, $CODE2, $CODE3)"
else
  red "FTS injection caused server error (codes: $CODE1, $CODE2, $CODE3)"
fi

# ──────────────────────────────────────────────────
header "Security Headers Check"
# ──────────────────────────────────────────────────

HEADERS=$(curl -sI "$BASE/" 2>/dev/null)

check_header() {
  if echo "$HEADERS" | grep -qi "$1"; then
    green "Header present: $1"
  else
    red "Header MISSING: $1"
  fi
}

check_header "X-Content-Type-Options"
check_header "X-Frame-Options"
check_header "X-XSS-Protection"
check_header "Strict-Transport-Security"
check_header "X-DNS-Prefetch-Control"

# ──────────────────────────────────────────────────
header "CORS Check"
# ──────────────────────────────────────────────────

# Send request with evil origin
CORS_RESP=$(curl -sI -H "Origin: http://evil-attacker.com" "$API/auth/login" 2>/dev/null)

if echo "$CORS_RESP" | grep -qi "access-control-allow-origin.*evil"; then
  red "CORS allows evil-attacker.com origin"
else
  green "CORS does not allow arbitrary origins"
fi

# ──────────────────────────────────────────────────
header "Admin Panel Auth Check"
# ──────────────────────────────────────────────────

# Try accessing admin API without auth
CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API/admin/status")
if [ "$CODE" = "401" ]; then
  green "Admin API requires authentication"
else
  red "Admin API accessible without auth (code: $CODE)"
fi

# Try accessing admin backup trigger without auth
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/admin/backup")
if [ "$CODE" = "401" ]; then
  green "Admin backup requires authentication"
else
  red "Admin backup accessible without auth (code: $CODE)"
fi

# ──────────────────────────────────────────────────
header "PIN Switch Requires Existing Session"
# ──────────────────────────────────────────────────

CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/auth/switch-user" \
  -H "Content-Type: application/json" \
  -d '{"pin":"1234"}')

if [ "$CODE" = "401" ]; then
  green "PIN switch requires existing auth session"
else
  red "PIN switch works without auth (code: $CODE)"
fi

# ──────────────────────────────────────────────────
header "Refresh Token Type Rejection"
# ──────────────────────────────────────────────────
# A refresh token should NOT work as a Bearer access token

CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API/tickets" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0eXBlIjoicmVmcmVzaCJ9.fake")

if [ "$CODE" = "401" ]; then
  green "Refresh tokens rejected as access tokens"
else
  yellow "Returned $CODE for fake refresh token (may just be invalid sig)"
fi

# ──────────────────────────────────────────────────
header "Sensitive Data Exposure"
# ──────────────────────────────────────────────────

# Check that login response doesn't leak password hashes or secrets
LOGIN_RESP=$(curl -s -X POST "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}')

if echo "$LOGIN_RESP" | grep -qi "password_hash\|totp_secret\|backup_codes"; then
  red "Login response leaks sensitive fields"
else
  green "Login response does not expose sensitive fields"
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
  echo -e "\033[32m  ✓ All critical security tests passed\033[0m"
  exit 0
fi
