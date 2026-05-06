-- WEB-UNWIRED-034 — durable manual membership billing runs.
--
-- Page-level "Run billing now" needs duplicate-run protection and a result
-- record instead of a toast-only placeholder. This table stores the run
-- lifecycle and per-subscription result summary for admin reporting.

CREATE TABLE IF NOT EXISTS membership_billing_runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  status TEXT NOT NULL DEFAULT 'running', -- running, completed, failed
  mode TEXT NOT NULL DEFAULT 'manual',
  started_at TEXT NOT NULL DEFAULT (datetime('now')),
  finished_at TEXT,
  started_by INTEGER REFERENCES users(id),
  total_due INTEGER NOT NULL DEFAULT 0,
  charged_count INTEGER NOT NULL DEFAULT 0,
  failed_count INTEGER NOT NULL DEFAULT 0,
  skipped_count INTEGER NOT NULL DEFAULT 0,
  result_json TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_membership_billing_runs_one_running
  ON membership_billing_runs(status)
  WHERE status = 'running';

CREATE INDEX IF NOT EXISTS idx_membership_billing_runs_started
  ON membership_billing_runs(started_at DESC);
