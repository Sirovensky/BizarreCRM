-- ENR-C7: Related/family accounts
CREATE TABLE IF NOT EXISTS customer_relationships (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id_a INTEGER NOT NULL REFERENCES customers(id),
  customer_id_b INTEGER NOT NULL REFERENCES customers(id),
  relationship_type TEXT NOT NULL DEFAULT 'family',
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_cr_a ON customer_relationships(customer_id_a);
CREATE INDEX IF NOT EXISTS idx_cr_b ON customer_relationships(customer_id_b);
