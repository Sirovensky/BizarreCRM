#!/bin/bash
# ============================================
# BizarreCRM Stress Test
# Sends a flood of random requests to test server resilience
# Usage: bash scripts/stress-test.sh [requests] [concurrency]
# ============================================

BASE="https://localhost:443"
TOTAL=${1:-500}
CONCURRENCY=${2:-20}
CURL="curl -sk --max-time 5"

echo "============================================"
echo " BizarreCRM Stress Test"
echo " Target: $BASE"
echo " Requests: $TOTAL | Concurrency: $CONCURRENCY"
echo "============================================"
echo ""

# Counters
PASS=0
FAIL=0
RATE_LIMITED=0
ERRORS=0
START_TIME=$(date +%s)

# Random endpoints to hit (mix of GET, POST, bad paths, bad methods)
ENDPOINTS=(
  "GET /api/v1/health"
  "GET /api/v1/tickets"
  "GET /api/v1/customers"
  "GET /api/v1/inventory"
  "GET /api/v1/invoices"
  "GET /api/v1/reports/sales"
  "GET /api/v1/search?q=test"
  "GET /api/v1/settings"
  "GET /api/v1/employees"
  "GET /api/v1/sms/threads"
  "GET /api/v1/leads"
  "GET /api/v1/estimates"
  "GET /api/v1/notifications"
  "POST /api/v1/auth/login"
  "POST /api/v1/auth/login"
  "POST /api/v1/auth/login"
  "GET /api/v1/nonexistent-endpoint"
  "GET /api/v1/../../../etc/passwd"
  "GET /api/v1/tickets?page=1&per_page=9999999"
  "POST /api/v1/tickets"
  "DELETE /api/v1/tickets/999999"
  "PUT /api/v1/customers/999999"
  "GET /super-admin/api/dashboard"
  "POST /super-admin/api/login"
  "GET /api/v1/management/stats"
  "GET /api/v1/admin/status"
  "GET /"
  "GET /health"
  "OPTIONS /api/v1/tickets"
  "PATCH /api/v1/settings"
)

# Random payloads for POST requests
PAYLOADS=(
  '{"username":"admin","password":"wrong"}'
  '{"username":"test","password":"test123"}'
  '{}'
  '{"garbage":true,"nested":{"deep":{"value":123}}}'
  '{"sql":"SELECT * FROM users; DROP TABLE users;--"}'
  '{"xss":"<script>alert(1)</script>"}'
  '{"huge":"'"$(python3 -c 'print("A"*10000)' 2>/dev/null || echo 'AAAAAAAAA')"'"}'
  'not-json-at-all'
  '{"username":"' "$(head -c 500 /dev/urandom | base64 | head -c 200)" '"}'
)

send_request() {
  local idx=$((RANDOM % ${#ENDPOINTS[@]}))
  local entry="${ENDPOINTS[$idx]}"
  local method="${entry%% *}"
  local path="${entry#* }"
  local url="${BASE}${path}"

  local args="-X $method"

  # Add random payload for POST/PUT/PATCH/DELETE
  if [[ "$method" == "POST" || "$method" == "PUT" || "$method" == "PATCH" ]]; then
    local pidx=$((RANDOM % ${#PAYLOADS[@]}))
    args="$args -H 'Content-Type: application/json' -d '${PAYLOADS[$pidx]}'"
  fi

  # Add random headers sometimes
  if (( RANDOM % 3 == 0 )); then
    args="$args -H 'X-Forwarded-For: $(( RANDOM % 256 )).$(( RANDOM % 256 )).$(( RANDOM % 256 )).$(( RANDOM % 256 ))'"
  fi
  if (( RANDOM % 4 == 0 )); then
    args="$args -H 'Authorization: Bearer fake-token-$(( RANDOM ))'"
  fi

  local status
  status=$(eval "$CURL -o /dev/null -w '%{http_code}' $args '$url'" 2>/dev/null)

  echo "$status"
}

echo "Sending $TOTAL requests with $CONCURRENCY concurrency..."
echo ""

# Run requests
for ((i=1; i<=TOTAL; i++)); do
  # Fire up to $CONCURRENCY in parallel
  send_request &

  # Throttle concurrency
  if (( i % CONCURRENCY == 0 )); then
    wait
    # Progress
    echo -ne "\r  Progress: $i / $TOTAL"
  fi
done
wait
echo -ne "\r  Progress: $TOTAL / $TOTAL"
echo ""
echo ""

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Final health check
echo "--- Post-stress health check ---"
HEALTH=$($CURL "$BASE/api/v1/health" 2>/dev/null)
if echo "$HEALTH" | grep -q '"ok"'; then
  echo "  Server: ALIVE"
else
  echo "  Server: DOWN or DEGRADED"
  echo "  Response: $HEALTH"
fi

# Check if PM2 shows it running
PM2_STATUS=$(pm2 jlist 2>/dev/null | grep -o '"status":"[^"]*"' | head -1)
echo "  PM2: $PM2_STATUS"

echo ""
echo "============================================"
echo " Stress test complete"
echo " Duration: ${DURATION}s"
echo " Requests: $TOTAL"
echo " Rate: $(( TOTAL / (DURATION + 1) )) req/s"
echo "============================================"
