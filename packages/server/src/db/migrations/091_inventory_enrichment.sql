-- =============================================================================
-- Migration 091 — Inventory / Parts Management Enrichment
-- =============================================================================
-- Adds schema for:
--   1.  Stocktakes (physical count with variance + audit trail)
--   2.  Bin locations (explicit row-shelf-bin registry + inventory junction)
--   3.  Serialized parts (per-unit status tracking)
--   4.  Shrinkage log (damaged / stolen / lost / expired, with photo)
--   5.  Supplier price comparison (multi-supplier per item)
--   6.  Supplier returns / RMA (credit tracking)
--   7.  Parts compatibility (device model tags)
--   8.  Lot warranty (never sell expired stock)
--
-- Cross-ref: criticalaudit.md §48 (Inventory / Parts Management).
-- NOTE: supplier-catalog add-to-inventory UI is intentionally OMITTED —
-- audit explicitly says "NO!" in §48 observations.
-- =============================================================================

-- Stocktakes — a physical count session
CREATE TABLE IF NOT EXISTS stocktakes (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  name                  TEXT NOT NULL,
  location              TEXT,
  status                TEXT NOT NULL DEFAULT 'open'
                          CHECK (status IN ('open', 'committed', 'cancelled')),
  opened_by_user_id     INTEGER,
  opened_at             TEXT NOT NULL DEFAULT (datetime('now')),
  committed_at          TEXT,
  committed_by_user_id  INTEGER,
  notes                 TEXT
);
CREATE INDEX IF NOT EXISTS idx_stocktakes_status ON stocktakes(status);
CREATE INDEX IF NOT EXISTS idx_stocktakes_opened_at ON stocktakes(opened_at);

-- Per-item count within a stocktake. UNIQUE(stocktake_id, inventory_item_id)
-- prevents the scanner from double-posting the same SKU — each re-scan should
-- UPSERT rather than insert a second row.
CREATE TABLE IF NOT EXISTS stocktake_counts (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  stocktake_id      INTEGER NOT NULL,
  inventory_item_id INTEGER NOT NULL,
  expected_qty      INTEGER NOT NULL,
  counted_qty       INTEGER NOT NULL,
  variance          INTEGER NOT NULL,
  notes             TEXT,
  counted_at        TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(stocktake_id, inventory_item_id)
);
CREATE INDEX IF NOT EXISTS idx_stocktake_counts_stocktake
  ON stocktake_counts(stocktake_id);

-- Bin locations — explicit registry so we can offer a dropdown in the
-- create/edit form. The existing `location`/`shelf`/`bin` columns on
-- inventory_items (migration 030) are free-text and get polluted with typos;
-- this table gives us a controlled vocabulary.
CREATE TABLE IF NOT EXISTS bin_locations (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  code         TEXT NOT NULL UNIQUE,
  description  TEXT,
  aisle        TEXT,
  shelf        TEXT,
  bin          TEXT,
  is_active    INTEGER NOT NULL DEFAULT 1
);

-- Junction table between inventory_items and bin_locations. Using a junction
-- instead of ALTER inventory_items lets us keep the inventory table stable
-- (it already has 20+ columns across 10+ migrations). One-to-one today but
-- easy to make many-to-many later if we add bin-based stock splits.
CREATE TABLE IF NOT EXISTS inventory_bin_assignments (
  inventory_item_id INTEGER PRIMARY KEY,
  bin_location_id   INTEGER NOT NULL,
  assigned_at       TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_inventory_bin_assignments_bin
  ON inventory_bin_assignments(bin_location_id);

-- Serialized part units. inventory_items.is_serialized is the switch; each
-- physical unit gets a row here with its own status lifecycle.
CREATE TABLE IF NOT EXISTS inventory_serial_numbers (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  inventory_item_id INTEGER NOT NULL,
  serial_number     TEXT NOT NULL,
  status            TEXT NOT NULL DEFAULT 'in_stock'
                      CHECK (status IN ('in_stock','sold','returned','defective','rma')),
  received_at       TEXT NOT NULL DEFAULT (datetime('now')),
  sold_at           TEXT,
  invoice_id        INTEGER,
  ticket_id         INTEGER,
  notes             TEXT,
  UNIQUE(inventory_item_id, serial_number)
);
CREATE INDEX IF NOT EXISTS idx_inventory_serials_item_status
  ON inventory_serial_numbers(inventory_item_id, status);

-- Shrinkage log — explicit "stock disappeared" event. Reason is constrained
-- and photo_path is optional (filed in /uploads/<tenant>/shrinkage).
CREATE TABLE IF NOT EXISTS inventory_shrinkage (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  inventory_item_id    INTEGER NOT NULL,
  quantity             INTEGER NOT NULL,
  reason               TEXT NOT NULL
                         CHECK (reason IN ('damaged','stolen','lost','expired','other')),
  photo_path           TEXT,
  reported_by_user_id  INTEGER,
  reported_at          TEXT NOT NULL DEFAULT (datetime('now')),
  notes                TEXT
);
CREATE INDEX IF NOT EXISTS idx_inventory_shrinkage_item
  ON inventory_shrinkage(inventory_item_id);
CREATE INDEX IF NOT EXISTS idx_inventory_shrinkage_reported_at
  ON inventory_shrinkage(reported_at);

-- Supplier price comparison. Three suppliers selling the same part at
-- different prices + lead times. UNIQUE prevents duplicate rows per
-- (item, supplier) — UPSERT on update.
CREATE TABLE IF NOT EXISTS supplier_prices (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  inventory_item_id INTEGER NOT NULL,
  supplier_id       INTEGER NOT NULL,
  supplier_sku      TEXT,
  price_cents       INTEGER NOT NULL,
  lead_time_days    INTEGER,
  moq               INTEGER NOT NULL DEFAULT 1,  -- min order qty
  last_updated_at   TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(inventory_item_id, supplier_id)
);
CREATE INDEX IF NOT EXISTS idx_supplier_prices_item
  ON supplier_prices(inventory_item_id);

-- Supplier returns / RMA with credit tracking.
CREATE TABLE IF NOT EXISTS supplier_returns (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  supplier_id         INTEGER NOT NULL,
  inventory_item_id   INTEGER NOT NULL,
  quantity            INTEGER NOT NULL,
  reason              TEXT,
  status              TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','approved','shipped','credited','rejected')),
  credit_amount_cents INTEGER,
  created_at          TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_supplier_returns_supplier
  ON supplier_returns(supplier_id);
CREATE INDEX IF NOT EXISTS idx_supplier_returns_status
  ON supplier_returns(status);

-- Parts compatibility many-to-many. device_model is a free-text string to
-- avoid coupling to the device_models table (which is replacement-catalog
-- driven and not always a 1:1 match with how parts are labelled).
CREATE TABLE IF NOT EXISTS inventory_compatibility (
  inventory_item_id INTEGER NOT NULL,
  device_model      TEXT NOT NULL,
  PRIMARY KEY (inventory_item_id, device_model)
);
CREATE INDEX IF NOT EXISTS idx_inventory_compatibility_model
  ON inventory_compatibility(device_model);

-- Per-lot warranty tracking. One inventory item may have multiple lots,
-- each with a different warranty_end_date. The POS / sell flow should
-- filter out lots whose warranty_end_date has passed.
CREATE TABLE IF NOT EXISTS inventory_lot_warranty (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  inventory_item_id INTEGER NOT NULL,
  lot_number        TEXT,
  warranty_end_date TEXT,
  quantity          INTEGER NOT NULL,
  received_at       TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_inventory_lot_warranty_item
  ON inventory_lot_warranty(inventory_item_id);
CREATE INDEX IF NOT EXISTS idx_inventory_lot_warranty_end
  ON inventory_lot_warranty(warranty_end_date);

-- Auto-reorder rules. Per-item override of the default reorder_level logic.
-- Existing inventory_items.reorder_level + desired_stock_level remain the
-- fallback; this table lets the shop set preferred_supplier_id and a
-- lead_time_days buffer so the auto-reorder run can pre-select correctly.
CREATE TABLE IF NOT EXISTS inventory_auto_reorder_rules (
  inventory_item_id     INTEGER PRIMARY KEY,
  min_qty               INTEGER NOT NULL,
  reorder_qty           INTEGER NOT NULL,
  preferred_supplier_id INTEGER,
  lead_time_days        INTEGER,
  is_enabled            INTEGER NOT NULL DEFAULT 1,
  updated_at            TEXT NOT NULL DEFAULT (datetime('now'))
);
