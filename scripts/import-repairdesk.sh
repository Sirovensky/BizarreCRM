#!/bin/bash
# ============================================================================
# RepairDesk → Bizarre CRM Full Import Script
# ============================================================================
#
# Usage:
#   ./scripts/import-repairdesk.sh [API_KEY] [SERVER_URL]
#
# Defaults:
#   API_KEY  = from .env file (RD_API_KEY)
#   SERVER_URL = http://localhost:3020
#
# Prerequisites:
#   - CRM server must be running
#   - Admin user must exist (admin/admin123)
#
# What it imports (in order):
#   1. Customers (with phones, emails)
#   2. Inventory items
#   3. Tickets (with devices, statuses, totals)
#   4. Invoices (with line items, payments)
#   5. SMS messages
#
# The import is idempotent — re-running skips already-imported records.
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load .env if exists
if [ -f "$PROJECT_DIR/.env" ]; then
  export $(grep -v '^#' "$PROJECT_DIR/.env" | xargs)
fi

API_KEY="${1:-$RD_API_KEY}"
SERVER_URL="${2:-http://localhost:3020}"

if [ -z "$API_KEY" ]; then
  echo "ERROR: No RepairDesk API key provided."
  echo "Usage: $0 <API_KEY> [SERVER_URL]"
  echo "Or set RD_API_KEY in .env"
  exit 1
fi

echo "============================================"
echo "  RepairDesk → Bizarre CRM Import"
echo "============================================"
echo "  Server:  $SERVER_URL"
echo "  API Key: ${API_KEY:0:10}..."
echo ""

# Login to get auth token
echo "→ Logging in..."
TOKEN=$(curl -sf -X POST "$SERVER_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}' \
  | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync(0,'utf8')).data.accessToken)")

if [ -z "$TOKEN" ]; then
  echo "ERROR: Failed to login. Is the server running?"
  exit 1
fi
echo "  ✓ Logged in"

# Test RepairDesk connection
echo ""
echo "→ Testing RepairDesk connection..."
TEST=$(curl -sf "$SERVER_URL/api/v1/import/repairdesk/test-connection?api_key=$API_KEY" \
  -H "Authorization: Bearer $TOKEN")
echo "  $TEST"

# Start full import
echo ""
echo "→ Starting full import (customers, inventory, tickets, invoices, sms)..."
IMPORT=$(curl -sf -X POST "$SERVER_URL/api/v1/import/repairdesk/start" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"api_key\":\"$API_KEY\",\"entities\":[\"customers\",\"inventory\",\"tickets\",\"invoices\",\"sms\"]}")
echo "  $IMPORT"

# Poll for completion
echo ""
echo "→ Waiting for import to complete..."
while true; do
  sleep 10
  STATUS=$(curl -sf "$SERVER_URL/api/v1/import/repairdesk/status" \
    -H "Authorization: Bearer $TOKEN")

  # Check if all runs are done
  PENDING=$(echo "$STATUS" | node -e "
    const j=JSON.parse(require('fs').readFileSync(0,'utf8'));
    const runs = j.data?.runs || [];
    const active = runs.filter(r => r.status === 'pending' || r.status === 'running');
    if (active.length > 0) {
      active.forEach(r => process.stderr.write('  [' + r.status + '] ' + r.entity_type + '\n'));
      process.stdout.write('active');
    } else {
      runs.forEach(r => process.stderr.write('  [' + r.status + '] ' + r.entity_type + ': ' + (r.records_imported||0) + ' imported, ' + (r.errors_count||0) + ' errors\n'));
      process.stdout.write('done');
    }
  " 2>&1)

  echo "$PENDING"

  if echo "$PENDING" | grep -q "done"; then
    break
  fi
done

echo ""
echo "============================================"
echo "  Import Complete!"
echo "============================================"

# Show final counts
curl -sf "$SERVER_URL/api/v1/import/repairdesk/status" \
  -H "Authorization: Bearer $TOKEN" \
  | node -e "
    const j=JSON.parse(require('fs').readFileSync(0,'utf8'));
    const runs = j.data?.runs || [];
    const latest = {};
    runs.forEach(r => { if (!latest[r.entity_type] || r.id > latest[r.entity_type].id) latest[r.entity_type] = r; });
    Object.values(latest).forEach(r => {
      const icon = r.status === 'completed' ? '✓' : r.status === 'failed' ? '✗' : '?';
      console.log('  ' + icon + ' ' + r.entity_type + ': ' + (r.records_imported||0) + ' imported, ' + (r.errors_count||0) + ' errors');
    });
  "
