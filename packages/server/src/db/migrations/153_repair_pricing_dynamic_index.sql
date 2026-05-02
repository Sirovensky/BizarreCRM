-- 153_repair_pricing_dynamic_index.sql
-- Backend foundation for the web/iOS repair-pricing matrix:
--   * tier-derived vs custom cell tracking
--   * supplier-cost/profit metadata for heatmaps and alerts
--   * row-level audit history for manual, tier, CSV, and auto-margin changes

ALTER TABLE repair_prices ADD COLUMN is_custom INTEGER NOT NULL DEFAULT 0 CHECK (is_custom IN (0, 1));
ALTER TABLE repair_prices ADD COLUMN tier_label TEXT;
ALTER TABLE repair_prices ADD COLUMN last_tier_rebase_at TEXT;
ALTER TABLE repair_prices ADD COLUMN profit_estimate REAL;
ALTER TABLE repair_prices ADD COLUMN profit_stale_at TEXT;
ALTER TABLE repair_prices ADD COLUMN auto_margin_enabled INTEGER NOT NULL DEFAULT 0 CHECK (auto_margin_enabled IN (0, 1));
ALTER TABLE repair_prices ADD COLUMN auto_margin_paused_at TEXT;
ALTER TABLE repair_prices ADD COLUMN last_supplier_cost REAL;
ALTER TABLE repair_prices ADD COLUMN last_supplier_seen_at TEXT;
ALTER TABLE repair_prices ADD COLUMN suggested_labor_price REAL;

CREATE TABLE IF NOT EXISTS repair_prices_audit (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  repair_price_id INTEGER REFERENCES repair_prices(id) ON DELETE SET NULL,
  device_model_id INTEGER REFERENCES device_models(id) ON DELETE SET NULL,
  repair_service_id INTEGER REFERENCES repair_services(id) ON DELETE SET NULL,
  old_labor_price REAL,
  new_labor_price REAL,
  old_is_custom INTEGER,
  new_is_custom INTEGER,
  old_tier_label TEXT,
  new_tier_label TEXT,
  supplier_cost REAL,
  profit_estimate REAL,
  source TEXT NOT NULL CHECK (
    source IN (
      'manual',
      'tier',
      'revert',
      'auto-margin',
      'supplier-recompute',
      'supplier-spike',
      'csv-import',
      'system'
    )
  ),
  changed_by_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  imported_filename TEXT,
  note TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_repair_prices_tier
  ON repair_prices(repair_service_id, tier_label, is_custom);
CREATE INDEX IF NOT EXISTS idx_repair_prices_profit_stale
  ON repair_prices(profit_stale_at)
  WHERE profit_stale_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_repair_prices_audit_price
  ON repair_prices_audit(repair_price_id, created_at);
CREATE INDEX IF NOT EXISTS idx_repair_prices_audit_device_service
  ON repair_prices_audit(device_model_id, repair_service_id, created_at);

INSERT OR IGNORE INTO store_config (key, value) VALUES
  ('repair_pricing_tier_a_years', '2'),
  ('repair_pricing_tier_b_years', '5'),
  ('repair_pricing_auto_margin_preset', 'mid_traffic'),
  ('repair_pricing_auto_margin_target_type', 'percent'),
  ('repair_pricing_auto_margin_target_pct', '100'),
  ('repair_pricing_auto_margin_target_profit_amount', '80'),
  ('repair_pricing_auto_margin_calculation_basis', 'markup'),
  ('repair_pricing_rounding_mode', 'ending_99'),
  ('repair_pricing_auto_margin_rules', '[]'),
  ('repair_pricing_target_profit_green', '80'),
  ('repair_pricing_target_profit_amber', '40'),
  ('repair_pricing_auto_margin_cap_pct', '25');
