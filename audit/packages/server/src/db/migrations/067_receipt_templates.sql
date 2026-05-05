-- ENR-I10: Receipt templates per payment method / invoice type
CREATE TABLE IF NOT EXISTS receipt_templates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'default',  -- default, warranty, trade_in, credit_note
  header_text TEXT,
  footer_text TEXT,
  show_warranty_info INTEGER NOT NULL DEFAULT 0,
  show_trade_in_info INTEGER NOT NULL DEFAULT 0,
  is_default INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT OR IGNORE INTO receipt_templates (name, type, is_default) VALUES ('Standard Receipt', 'default', 1);
INSERT OR IGNORE INTO receipt_templates (name, type, show_warranty_info) VALUES ('Warranty Receipt', 'warranty', 1);
INSERT OR IGNORE INTO receipt_templates (name, type, show_trade_in_info) VALUES ('Trade-In Receipt', 'trade_in', 1);
