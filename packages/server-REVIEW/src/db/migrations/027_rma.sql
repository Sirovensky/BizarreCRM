-- Return Merchandise Authorization for defective supplier parts
CREATE TABLE IF NOT EXISTS rma_requests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id TEXT UNIQUE,  -- RMA-0001
  supplier_id INTEGER REFERENCES suppliers(id),
  supplier_name TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'approved', 'shipped', 'received', 'resolved', 'declined')),
  reason TEXT,
  notes TEXT,
  tracking_number TEXT,
  created_by INTEGER NOT NULL REFERENCES users(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS rma_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  rma_id INTEGER NOT NULL REFERENCES rma_requests(id) ON DELETE CASCADE,
  inventory_item_id INTEGER REFERENCES inventory_items(id),
  ticket_device_part_id INTEGER REFERENCES ticket_device_parts(id),
  name TEXT NOT NULL,
  quantity INTEGER NOT NULL DEFAULT 1,
  reason TEXT,  -- defective, wrong_item, damaged, etc.
  resolution TEXT  -- replace, refund, credit
);

CREATE INDEX IF NOT EXISTS idx_rma_supplier ON rma_requests(supplier_id);
