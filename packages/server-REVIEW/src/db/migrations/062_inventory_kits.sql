-- ENR-INV11: Kit/bundle definitions
CREATE TABLE IF NOT EXISTS inventory_kits (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS inventory_kit_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kit_id INTEGER NOT NULL REFERENCES inventory_kits(id),
  inventory_item_id INTEGER NOT NULL REFERENCES inventory_items(id),
  quantity INTEGER NOT NULL DEFAULT 1
);
