-- Refunds, store credits, and credit notes
CREATE TABLE IF NOT EXISTS refunds (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_id INTEGER REFERENCES invoices(id),
  ticket_id INTEGER REFERENCES tickets(id),
  customer_id INTEGER REFERENCES customers(id),
  amount REAL NOT NULL,
  type TEXT NOT NULL DEFAULT 'refund' CHECK(type IN ('refund', 'store_credit', 'credit_note')),
  reason TEXT,
  method TEXT,  -- cash, card, store_credit, original_method
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'approved', 'completed', 'declined')),
  approved_by INTEGER REFERENCES users(id),
  created_by INTEGER NOT NULL REFERENCES users(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS store_credits (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  amount REAL NOT NULL DEFAULT 0,  -- Current balance
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS store_credit_transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  amount REAL NOT NULL,  -- Positive = credit added, negative = credit used
  type TEXT NOT NULL CHECK(type IN ('refund_credit', 'manual_credit', 'usage', 'adjustment')),
  reference_type TEXT,  -- refund, invoice, manual
  reference_id INTEGER,
  notes TEXT,
  user_id INTEGER REFERENCES users(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_refunds_invoice ON refunds(invoice_id);
CREATE INDEX IF NOT EXISTS idx_refunds_customer ON refunds(customer_id);
CREATE INDEX IF NOT EXISTS idx_store_credits_customer ON store_credits(customer_id);
CREATE INDEX IF NOT EXISTS idx_credit_transactions_customer ON store_credit_transactions(customer_id);
