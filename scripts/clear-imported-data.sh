#!/bin/bash
# ============================================================================
# Clear Imported Data (keep manual entries, remove RepairDesk imports)
# ============================================================================
#
# Usage:
#   ./scripts/clear-imported-data.sh [ENTITY]
#
#   ENTITY = all | customers | tickets | invoices | inventory | sms
#   Default: all
#
# This removes data that was imported from RepairDesk (tracked in import_id_map)
# while preserving manually created records.
#
# The server must be STOPPED before running this (SQLite locking).
# ============================================================================

set -e

# PROD77: hard-block in production. Deletes imported customer / ticket /
# invoice / inventory / SMS rows — OK in dev when re-running an import,
# catastrophic against a live tenant.
if [ "${NODE_ENV:-development}" = "production" ]; then
  echo "ERROR: refusing to clear imported data with NODE_ENV=production"
  echo "This script deletes customer / ticket / invoice rows. Irreversible."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DB_PATH="$PROJECT_DIR/packages/server/data/bizarre-crm.db"

ENTITY="${1:-all}"

if [ ! -f "$DB_PATH" ]; then
  echo "ERROR: Database not found at $DB_PATH"
  exit 1
fi

echo "============================================"
echo "  Clear Imported Data"
echo "============================================"
echo "  Entity: $ENTITY"
echo "  Database: $DB_PATH"
echo ""
echo "  Make sure the server is STOPPED first!"
echo ""

read -p "  Continue? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
  echo "  Aborted."
  exit 0
fi

cd "$PROJECT_DIR/packages/server"

node -e "
const Database = require('better-sqlite3');
const db = new Database('$DB_PATH');
db.pragma('foreign_keys = OFF');

const entity = '$ENTITY';

function clearEntity(type) {
  const ids = db.prepare('SELECT local_id FROM import_id_map WHERE entity_type = ?').all(type).map(r => r.local_id);
  if (ids.length === 0) { console.log('  ' + type + ': nothing to clear'); return; }

  for (let i = 0; i < ids.length; i += 500) {
    const batch = ids.slice(i, i + 500).join(',');

    if (type === 'ticket') {
      try { db.exec('DELETE FROM ticket_device_parts WHERE ticket_device_id IN (SELECT id FROM ticket_devices WHERE ticket_id IN (' + batch + '))'); } catch(e) {}
      try { db.exec('DELETE FROM ticket_notes WHERE ticket_id IN (' + batch + ')'); } catch(e) {}
      try { db.exec('DELETE FROM ticket_history WHERE ticket_id IN (' + batch + ')'); } catch(e) {}
      try { db.exec('DELETE FROM ticket_devices WHERE ticket_id IN (' + batch + ')'); } catch(e) {}
      db.exec('DELETE FROM tickets WHERE id IN (' + batch + ')');
    }
    else if (type === 'invoice') {
      try { db.exec('DELETE FROM invoice_line_items WHERE invoice_id IN (' + batch + ')'); } catch(e) {}
      try { db.exec('DELETE FROM payments WHERE invoice_id IN (' + batch + ')'); } catch(e) {}
      db.exec('DELETE FROM invoices WHERE id IN (' + batch + ')');
    }
    else if (type === 'customer') {
      try { db.exec('DELETE FROM customer_phones WHERE customer_id IN (' + batch + ')'); } catch(e) {}
      try { db.exec('DELETE FROM customer_emails WHERE customer_id IN (' + batch + ')'); } catch(e) {}
      db.exec('DELETE FROM customers WHERE id IN (' + batch + ')');
    }
    else if (type === 'inventory') {
      try { db.exec('DELETE FROM inventory_serials WHERE inventory_item_id IN (' + batch + ')'); } catch(e) {}
      db.exec('DELETE FROM inventory_items WHERE id IN (' + batch + ')');
    }
    else if (type === 'sms') {
      db.exec('DELETE FROM sms_messages WHERE id IN (' + batch + ')');
    }
  }
  db.exec('DELETE FROM import_id_map WHERE entity_type = \"' + type + '\"');
  console.log('  ✓ ' + type + ': cleared ' + ids.length + ' records');
}

if (entity === 'all') {
  // Order matters: invoices before tickets, tickets before customers
  clearEntity('invoice');
  clearEntity('ticket');
  clearEntity('sms');
  clearEntity('inventory');
  clearEntity('customer');
} else {
  const typeMap = { customers: 'customer', tickets: 'ticket', invoices: 'invoice', inventory: 'inventory', sms: 'sms' };
  clearEntity(typeMap[entity] || entity);
}

console.log('');
console.log('  Remaining counts:');
console.log('    Customers:', db.prepare('SELECT COUNT(*) as c FROM customers').get().c);
console.log('    Tickets:', db.prepare('SELECT COUNT(*) as c FROM tickets').get().c);
console.log('    Invoices:', db.prepare('SELECT COUNT(*) as c FROM invoices').get().c);
console.log('    Inventory:', db.prepare('SELECT COUNT(*) as c FROM inventory_items').get().c);
console.log('    SMS:', db.prepare('SELECT COUNT(*) as c FROM sms_messages').get().c);

db.close();
"

echo ""
echo "  Done. Start the server and re-import if needed."
