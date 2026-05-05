-- ─────────────────────────────────────────────────────────────────────────────
-- 002: manufacturers, device models, supplier catalog
-- ─────────────────────────────────────────────────────────────────────────────

-- Manufacturers
CREATE TABLE IF NOT EXISTS manufacturers (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT NOT NULL UNIQUE,
  slug        TEXT NOT NULL UNIQUE,
  logo_url    TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Device models (phones, tablets, laptops, consoles, etc.)
CREATE TABLE IF NOT EXISTS device_models (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  manufacturer_id INTEGER NOT NULL REFERENCES manufacturers(id),
  name            TEXT NOT NULL,          -- "iPhone 14 Pro"
  slug            TEXT NOT NULL,          -- "iphone-14-pro"
  category        TEXT NOT NULL DEFAULT 'phone', -- phone|tablet|laptop|console|other
  release_year    INTEGER,
  is_popular      INTEGER NOT NULL DEFAULT 0, -- 1 = show in quick-select
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(manufacturer_id, name)
);
CREATE INDEX IF NOT EXISTS idx_device_models_manufacturer ON device_models(manufacturer_id);
CREATE INDEX IF NOT EXISTS idx_device_models_category ON device_models(category);

-- FTS for device model search
CREATE VIRTUAL TABLE IF NOT EXISTS device_models_fts USING fts5(
  name,
  manufacturer_name,
  content='',
  tokenize='porter unicode61'
);

-- Supplier catalog (products from Mobilesentrix / PhoneLcdParts etc.)
CREATE TABLE IF NOT EXISTS supplier_catalog (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  source              TEXT NOT NULL,   -- 'mobilesentrix' | 'phonelcdparts'
  external_id         TEXT,            -- supplier's product ID
  sku                 TEXT,
  name                TEXT NOT NULL,
  description         TEXT,
  category            TEXT,
  price               REAL NOT NULL DEFAULT 0,
  compare_price       REAL,
  image_url           TEXT,
  product_url         TEXT,
  tags                TEXT,            -- JSON array of tags
  compatible_devices  TEXT,            -- JSON array of parsed device model names
  in_stock            INTEGER NOT NULL DEFAULT 1,
  last_synced         TEXT NOT NULL DEFAULT (datetime('now')),
  created_at          TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(source, external_id)
);
CREATE INDEX IF NOT EXISTS idx_supplier_catalog_source ON supplier_catalog(source);
CREATE INDEX IF NOT EXISTS idx_supplier_catalog_sku ON supplier_catalog(sku);

-- FTS for supplier catalog search
CREATE VIRTUAL TABLE IF NOT EXISTS supplier_catalog_fts USING fts5(
  name,
  description,
  tags,
  content='',
  tokenize='porter unicode61'
);

-- Link between inventory items and device models (many-to-many)
CREATE TABLE IF NOT EXISTS inventory_device_compatibility (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  inventory_item_id INTEGER NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
  device_model_id   INTEGER NOT NULL REFERENCES device_models(id) ON DELETE CASCADE,
  UNIQUE(inventory_item_id, device_model_id)
);
CREATE INDEX IF NOT EXISTS idx_inv_compat_item ON inventory_device_compatibility(inventory_item_id);
CREATE INDEX IF NOT EXISTS idx_inv_compat_model ON inventory_device_compatibility(device_model_id);

-- Link between supplier catalog items and device models
CREATE TABLE IF NOT EXISTS catalog_device_compatibility (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  supplier_catalog_id INTEGER NOT NULL REFERENCES supplier_catalog(id) ON DELETE CASCADE,
  device_model_id     INTEGER NOT NULL REFERENCES device_models(id) ON DELETE CASCADE,
  UNIQUE(supplier_catalog_id, device_model_id)
);
CREATE INDEX IF NOT EXISTS idx_cat_compat_catalog ON catalog_device_compatibility(supplier_catalog_id);
CREATE INDEX IF NOT EXISTS idx_cat_compat_model ON catalog_device_compatibility(device_model_id);

-- Scrape jobs log
CREATE TABLE IF NOT EXISTS scrape_jobs (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  source        TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'pending', -- pending|running|done|failed
  total_pages   INTEGER,
  pages_done    INTEGER DEFAULT 0,
  items_upserted INTEGER DEFAULT 0,
  error         TEXT,
  started_at    TEXT,
  finished_at   TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);
