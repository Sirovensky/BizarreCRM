-- 154_margin_alerts.sql
-- Tracks repair-price rows whose profit_estimate has stayed below the
-- amber threshold for 7+ consecutive days. Auto-resolves when profit
-- recovers. Powers dashboard chip + weekly email digest (DPI-7).

CREATE TABLE IF NOT EXISTS margin_alerts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  repair_price_id INTEGER NOT NULL REFERENCES repair_prices(id) ON DELETE CASCADE,
  device_model_id INTEGER NOT NULL REFERENCES device_models(id) ON DELETE CASCADE,
  repair_service_id INTEGER NOT NULL REFERENCES repair_services(id) ON DELETE CASCADE,
  tier_label TEXT,
  labor_price REAL NOT NULL,
  supplier_cost REAL,
  profit_estimate REAL,
  amber_threshold REAL NOT NULL,
  first_seen_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at TEXT NOT NULL DEFAULT (datetime('now')),
  resolved_at TEXT,
  acked_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_margin_alerts_active_price
  ON margin_alerts(repair_price_id)
  WHERE resolved_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_margin_alerts_unresolved
  ON margin_alerts(resolved_at)
  WHERE resolved_at IS NULL;
