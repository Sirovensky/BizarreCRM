-- ─────────────────────────────────────────────────────────────────────────────
-- 003: parts status tracking + missing-parts order queue
-- ─────────────────────────────────────────────────────────────────────────────

-- Add status and supplier tracking to ticket_device_parts
ALTER TABLE ticket_device_parts ADD COLUMN status TEXT NOT NULL DEFAULT 'available';
-- 'available'  — part is in stock, already reserved/used
-- 'missing'    — part not in our inventory; needs to be ordered
-- 'ordered'    — purchase order placed (or added to order queue)
-- 'received'   — arrived, ready to use

ALTER TABLE ticket_device_parts ADD COLUMN catalog_item_id INTEGER REFERENCES supplier_catalog(id) ON DELETE SET NULL;
-- Link to the supplier_catalog row this part came from (if added via catalog search)

ALTER TABLE ticket_device_parts ADD COLUMN supplier_url TEXT;
-- Direct product URL on supplier website for quick ordering

-- ─────────────────────────────────────────────────────────────────────────────
-- parts_order_queue — aggregated list of missing parts to order
-- One row per unique part needed. Multiple tickets may reference the same part.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS parts_order_queue (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  source              TEXT NOT NULL,          -- 'mobilesentrix' | 'phonelcdparts' | 'manual'
  catalog_item_id     INTEGER REFERENCES supplier_catalog(id) ON DELETE SET NULL,
  inventory_item_id   INTEGER REFERENCES inventory_items(id) ON DELETE SET NULL,
  name                TEXT NOT NULL,
  sku                 TEXT,
  supplier_url        TEXT,
  image_url           TEXT,
  unit_price          REAL NOT NULL DEFAULT 0,
  quantity_needed     INTEGER NOT NULL DEFAULT 1,  -- total qty across all tickets
  status              TEXT NOT NULL DEFAULT 'pending',
  -- pending   = not yet ordered
  -- ordered   = marked as ordered (link clicked or PO created)
  -- received  = arrived in shop
  -- cancelled = no longer needed
  notes               TEXT,
  created_at          TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Link queue items back to the ticket_device_parts rows that drove the request
CREATE TABLE IF NOT EXISTS parts_order_queue_tickets (
  id                      INTEGER PRIMARY KEY AUTOINCREMENT,
  parts_order_queue_id    INTEGER NOT NULL REFERENCES parts_order_queue(id) ON DELETE CASCADE,
  ticket_device_part_id   INTEGER NOT NULL REFERENCES ticket_device_parts(id) ON DELETE CASCADE,
  ticket_id               INTEGER NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  quantity                INTEGER NOT NULL DEFAULT 1,
  UNIQUE(parts_order_queue_id, ticket_device_part_id)
);

CREATE INDEX IF NOT EXISTS idx_parts_order_status ON parts_order_queue(status);
CREATE INDEX IF NOT EXISTS idx_parts_order_source ON parts_order_queue(source);
