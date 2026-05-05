-- Gift card system
CREATE TABLE IF NOT EXISTS gift_cards (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL UNIQUE,  -- 16-char alphanumeric
  initial_balance REAL NOT NULL,
  current_balance REAL NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active', 'used', 'expired', 'disabled')),
  customer_id INTEGER REFERENCES customers(id),  -- optional: who purchased it
  recipient_name TEXT,
  recipient_email TEXT,
  expires_at TEXT,
  notes TEXT,
  created_by INTEGER REFERENCES users(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS gift_card_transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  gift_card_id INTEGER NOT NULL REFERENCES gift_cards(id),
  type TEXT NOT NULL CHECK(type IN ('purchase', 'redemption', 'refund', 'adjustment')),
  amount REAL NOT NULL,  -- positive = credit, negative = debit
  invoice_id INTEGER REFERENCES invoices(id),
  notes TEXT,
  user_id INTEGER REFERENCES users(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_gift_card_code ON gift_cards(code);
CREATE INDEX IF NOT EXISTS idx_gift_card_customer ON gift_cards(customer_id);
