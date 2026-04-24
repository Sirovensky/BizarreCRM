-- Migration 122: Inventory variants + bundles
-- SCAN-486, SCAN-487
-- Money columns are INTEGER cents per SEC-H34 (no REAL).

-- ---------------------------------------------------------------------------
-- inventory_variants
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS inventory_variants (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  parent_item_id       INTEGER NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
  sku                  TEXT    NOT NULL UNIQUE,
  variant_type         TEXT    NOT NULL,        -- e.g. "color", "size", "storage"
  variant_value        TEXT    NOT NULL,        -- e.g. "Black", "128GB"
  retail_price_cents   INTEGER NOT NULL CHECK(retail_price_cents >= 0),
  cost_price_cents     INTEGER NOT NULL DEFAULT 0 CHECK(cost_price_cents >= 0),
  in_stock             INTEGER NOT NULL DEFAULT 0 CHECK(in_stock >= 0),
  is_active            INTEGER NOT NULL DEFAULT 1,
  created_at           TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now')),
  updated_at           TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now')),
  UNIQUE (parent_item_id, variant_type, variant_value)
);

CREATE INDEX IF NOT EXISTS idx_inventory_variants_parent ON inventory_variants(parent_item_id);

-- ---------------------------------------------------------------------------
-- inventory_bundles
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS inventory_bundles (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  name               TEXT    NOT NULL,
  sku                TEXT    NOT NULL UNIQUE,
  retail_price_cents INTEGER NOT NULL CHECK(retail_price_cents >= 0),
  description        TEXT,
  is_active          INTEGER NOT NULL DEFAULT 1,
  created_at         TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now')),
  updated_at         TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now'))
);

-- ---------------------------------------------------------------------------
-- inventory_bundle_items
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS inventory_bundle_items (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  bundle_id  INTEGER NOT NULL REFERENCES inventory_bundles(id) ON DELETE CASCADE,
  item_id    INTEGER NOT NULL REFERENCES inventory_items(id),
  variant_id INTEGER          REFERENCES inventory_variants(id),
  qty        INTEGER NOT NULL CHECK(qty > 0),
  created_at TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now')),
  UNIQUE (bundle_id, item_id, variant_id)
);

CREATE INDEX IF NOT EXISTS idx_inventory_bundle_items_bundle ON inventory_bundle_items(bundle_id);
