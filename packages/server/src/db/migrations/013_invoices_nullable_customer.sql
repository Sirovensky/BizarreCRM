-- Allow invoices without a customer (walk-in POS sales)
-- SQLite doesn't support ALTER COLUMN, so we recreate the table
PRAGMA foreign_keys = OFF;

CREATE TABLE invoices_new (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id TEXT NOT NULL,
  ticket_id INTEGER REFERENCES tickets(id),
  customer_id INTEGER REFERENCES customers(id),  -- NOW NULLABLE
  status TEXT NOT NULL DEFAULT 'draft',
  subtotal REAL NOT NULL DEFAULT 0,
  discount REAL NOT NULL DEFAULT 0,
  discount_reason TEXT,
  total_tax REAL NOT NULL DEFAULT 0,
  total REAL NOT NULL DEFAULT 0,
  amount_paid REAL NOT NULL DEFAULT 0,
  amount_due REAL NOT NULL DEFAULT 0,
  due_on TEXT,
  notes TEXT,
  created_by INTEGER REFERENCES users(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO invoices_new SELECT * FROM invoices;
DROP TABLE invoices;
ALTER TABLE invoices_new RENAME TO invoices;

CREATE INDEX IF NOT EXISTS idx_invoices_customer ON invoices(customer_id);
CREATE INDEX IF NOT EXISTS idx_invoices_ticket ON invoices(ticket_id);
CREATE INDEX IF NOT EXISTS idx_invoices_created ON invoices(created_at);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON invoices(status);

PRAGMA foreign_keys = ON;
