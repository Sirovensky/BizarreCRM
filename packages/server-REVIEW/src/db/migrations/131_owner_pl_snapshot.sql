-- Migration 131: Owner P&L Snapshot table
-- SCAN-467: Owner P&L / financial dashboard aggregator (android §62 / ios §59)
-- Stores admin-triggered point-in-time P&L snapshots.
-- Live GET /summary queries do NOT use this table — it is only written on
-- POST /api/v1/owner-pl/snapshot.

CREATE TABLE IF NOT EXISTS pl_snapshots (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  -- tenant_slug_hint is informational only; NOT used in multi-tenant
  -- queries. Security: cache is keyed by resolved tenantSlug from
  -- req.tenantSlug, not this column.
  tenant_slug_hint      TEXT,
  period_from           TEXT NOT NULL,
  period_to             TEXT NOT NULL,
  revenue_cents         INTEGER,
  cogs_cents            INTEGER,
  gross_profit_cents    INTEGER,
  expense_cents         INTEGER,
  net_profit_cents      INTEGER,
  tax_liability_cents   INTEGER,
  outstanding_ar_cents  INTEGER,
  inventory_value_cents INTEGER,
  metadata_json         TEXT,
  generated_at          TEXT DEFAULT (datetime('now')),
  generated_by_user_id  INTEGER REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_pl_snapshots_period
  ON pl_snapshots (period_from, period_to);
