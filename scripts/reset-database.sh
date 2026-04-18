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

# PROD77: hard-block in production. This script wipes the entire database
# and uploads directory — running it against a live tenant would be
# catastrophic. Require NODE_ENV != production AND an explicit confirmation
# flag so no one can nuke a live DB by tab-completing a filename.
if [ "${NODE_ENV:-development}" = "production" ]; then
  echo "ERROR: refusing to reset database with NODE_ENV=production"
  echo "This is a destructive, irreversible operation."
  echo "If you really need to do this, unset NODE_ENV or run with NODE_ENV=development."
  exit 1
fi

if [ "${CONFIRM_RESET:-}" != "yes" ]; then
  echo "This will permanently delete the database + all uploads."
  echo "Re-run with CONFIRM_RESET=yes to proceed."
  exit 1
fi

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
