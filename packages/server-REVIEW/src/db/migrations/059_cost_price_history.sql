-- ENR-INV10: Historical cost tracking
CREATE TABLE IF NOT EXISTS cost_price_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  inventory_item_id INTEGER NOT NULL REFERENCES inventory_items(id),
  old_price REAL,
  new_price REAL NOT NULL,
  changed_by INTEGER REFERENCES users(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_cph_item ON cost_price_history(inventory_item_id);
