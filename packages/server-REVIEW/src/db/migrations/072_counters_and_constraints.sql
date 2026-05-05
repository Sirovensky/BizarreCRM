-- Counters table — single source of truth for ticket/invoice/PO numbering.
-- Prevents:
--   I4: MAX(CAST(SUBSTR(order_id,3) AS INTEGER)) poisoning by Android-generated negatives
--   I5: Same pattern on invoice_number / credit_note_number
--   I6: Same pattern on PO numbers
--   I7: Concurrent SKU import overlap via MAX(id)+1
--   Race conditions between two concurrent inserts (no MAX + transaction)
--
-- Usage (see utils/counters.ts):
--   allocateCounter(db, 'ticket_order_id') returns the next sequential integer,
--   atomically UPDATE counters SET value = value + 1 RETURNING value.
--
-- Seed: existing MAX values on startup (safe because existing IDs are positive).
-- Negative IDs (Android bug) are filtered out via GLOB '[0-9]*' / T-[0-9]*.
CREATE TABLE IF NOT EXISTS counters (
  name TEXT PRIMARY KEY,
  value INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT OR IGNORE INTO counters (name, value) VALUES
  ('ticket_order_id',  (SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 3) AS INTEGER)), 0) FROM tickets   WHERE order_id GLOB 'T-[0-9]*')),
  ('invoice_order_id', (SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0) FROM invoices  WHERE order_id GLOB 'INV-[0-9]*')),
  ('credit_note_id',   0),
  ('po_number',        0),
  ('inventory_sku',    (SELECT COALESCE(MAX(id), 0) FROM inventory_items));

-- Backstop unique constraint: prevent two tickets with the same order_id.
-- Existing indexes (044_invoice_orderid_unique.sql) handle invoices.
CREATE UNIQUE INDEX IF NOT EXISTS idx_tickets_order_id_unique
  ON tickets(order_id) WHERE order_id IS NOT NULL AND order_id != '';

-- Prevent negative order_id values from reaching the DB in the first place.
-- Can't add a CHECK constraint to an existing table in SQLite without rebuilding,
-- but application-layer validation is enforced in utils/counters.ts + route handlers.
