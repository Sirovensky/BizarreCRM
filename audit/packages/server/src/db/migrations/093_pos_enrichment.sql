-- ============================================================================
-- Migration 093 — POS Daily Flow enrichment (audit §43)
-- ============================================================================
--
-- Adds the schema backing the POS "cashier" workflow enrichment layer on top
-- of the existing pos.routes.ts / invoices.routes.ts owned by other agents.
--
-- This migration is PURELY ADDITIVE. It never redeclares tables owned by
-- prior migrations and never drops columns. Re-running it is a no-op thanks
-- to IF NOT EXISTS / INSERT OR IGNORE.
--
-- Covers ideas from §43 that need persistent state:
--   4.  Cash drawer reconciliation  → cash_drawer_shifts
--   8.  Shift clock-in/out w/ POS   → cash_drawer_shifts (reused)
--   12. Manager PIN on high-value   → store_config.pos_manager_pin_threshold
--   9.  Upsell prompts by category  → store_config.pos_upsell_enabled
--   13. Active sale inactivity rst  → store_config.pos_inactivity_minutes
--   15. Training / sandbox mode     → pos_training_sessions
--
-- All money columns are INTEGER cents to avoid float-drift bugs (POS5 class).
-- ============================================================================

-- ── Cash drawer shifts ─────────────────────────────────────────────────────
-- One row per shift. Open shift = closed_at IS NULL. The variance is stored
-- so Z-reports can be re-rendered without re-computing historical sales.
CREATE TABLE IF NOT EXISTS cash_drawer_shifts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  opened_by_user_id INTEGER NOT NULL,
  opened_at TEXT NOT NULL DEFAULT (datetime('now')),
  opening_float_cents INTEGER NOT NULL DEFAULT 0,
  closed_by_user_id INTEGER,
  closed_at TEXT,
  closing_counted_cents INTEGER,
  expected_cents INTEGER,
  variance_cents INTEGER,
  z_report_json TEXT,
  notes TEXT
);

-- Fast lookup for "is there an open shift right now?" — partial index on NULL
-- closed_at. Only ever 0 or 1 rows at a time in a typical shop.
CREATE INDEX IF NOT EXISTS idx_drawer_shifts_open
  ON cash_drawer_shifts(closed_at)
  WHERE closed_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_drawer_shifts_opened_at
  ON cash_drawer_shifts(opened_at);

-- ── POS training / sandbox sessions ────────────────────────────────────────
-- When a user starts training mode we create a row. Fake transactions are
-- recorded as a JSON blob, never hitting inventory_items or payments tables.
-- This keeps new-hire practice runs from polluting analytics.
CREATE TABLE IF NOT EXISTS pos_training_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  started_at TEXT NOT NULL DEFAULT (datetime('now')),
  ended_at TEXT,
  fake_transactions_json TEXT
);

CREATE INDEX IF NOT EXISTS idx_pos_training_user
  ON pos_training_sessions(user_id);

CREATE INDEX IF NOT EXISTS idx_pos_training_open
  ON pos_training_sessions(ended_at)
  WHERE ended_at IS NULL;

-- ── Store-config flags for POS enrichment ──────────────────────────────────
-- pos_manager_pin_threshold: cents threshold above which a manager PIN is
--   required on checkout. NULL / 0 disables the check. Default 50000 = $500.
-- pos_upsell_enabled: 1 to show "customer bought a screen → suggest a case"
--   prompts, 0 to hide them globally.
-- pos_inactivity_minutes: minutes before an idle POS session auto-resets to
--   the default view (only when an existing ticket is loaded).
-- pos_training_mode_default: 1 to start new employees in sandbox mode by
--   default, 0 to require opt-in per-session.
INSERT OR IGNORE INTO store_config (key, value) VALUES
  ('pos_manager_pin_threshold', '50000'),
  ('pos_upsell_enabled', '1'),
  ('pos_inactivity_minutes', '10'),
  ('pos_training_mode_default', '0');
