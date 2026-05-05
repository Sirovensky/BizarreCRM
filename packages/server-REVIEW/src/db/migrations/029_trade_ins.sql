-- Trade-in / buyback program
CREATE TABLE IF NOT EXISTS trade_ins (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER REFERENCES customers(id),
  device_name TEXT NOT NULL,
  device_type TEXT,
  imei TEXT,
  serial TEXT,
  color TEXT,
  condition TEXT NOT NULL DEFAULT 'good' CHECK(condition IN ('excellent', 'good', 'fair', 'poor', 'broken')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'evaluated', 'accepted', 'declined', 'completed', 'scrapped')),
  offered_price REAL DEFAULT 0,
  accepted_price REAL,
  notes TEXT,
  pre_conditions TEXT,  -- JSON array of condition checks
  evaluated_by INTEGER REFERENCES users(id),
  created_by INTEGER NOT NULL REFERENCES users(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_trade_ins_customer ON trade_ins(customer_id);
CREATE INDEX IF NOT EXISTS idx_trade_ins_status ON trade_ins(status);
