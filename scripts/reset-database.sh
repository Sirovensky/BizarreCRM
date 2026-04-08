#!/bin/bash
# ============================================================================
# Reset Bizarre CRM Database to Clean State
# ============================================================================
#
# WARNING: This deletes ALL data and starts fresh!
#
# Usage:
#   ./scripts/reset-database.sh
#
# What it does:
#   1. Stops any running server
#   2. Deletes the SQLite database file
#   3. Deletes uploaded files
#   4. On next server start, migrations re-run and seed data is applied
#
# After running this, start the server normally:
#   cd packages/server && npx tsx src/index.ts
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DB_PATH="$PROJECT_DIR/packages/server/data/bizarre-crm.db"
UPLOADS_PATH="$PROJECT_DIR/packages/server/uploads"

echo "============================================"
echo "  Bizarre CRM — Database Reset"
echo "============================================"
echo ""
echo "  WARNING: This will DELETE all data!"
echo "  Database: $DB_PATH"
echo "  Uploads:  $UPLOADS_PATH"
echo ""

read -p "  Are you sure? (type YES to confirm): " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
  echo "  Aborted."
  exit 0
fi

echo ""

# Delete database files
if [ -f "$DB_PATH" ]; then
  rm -f "$DB_PATH" "$DB_PATH-wal" "$DB_PATH-shm"
  echo "  ✓ Deleted database"
else
  echo "  - Database not found (already clean)"
fi

# Clear uploads (keep directory)
if [ -d "$UPLOADS_PATH" ]; then
  rm -rf "$UPLOADS_PATH"/*
  echo "  ✓ Cleared uploads"
else
  mkdir -p "$UPLOADS_PATH"
  echo "  ✓ Created uploads directory"
fi

echo ""
echo "  Database reset complete."
echo "  Start the server to recreate with fresh seed data:"
echo ""
echo "    cd packages/server && npx tsx src/index.ts"
echo ""
echo "  Then run the import script to import RepairDesk data:"
echo ""
echo "    ./scripts/import-repairdesk.sh"
echo ""
