-- Migration 126: Estimate e-sign tokens/signatures + data export schedules
-- SCAN-494: Public customer e-sign flow (single-use HMAC tokens + captured signatures)
-- SCAN-498: Data export scheduling + cron (periodic automated exports with delivery)

-- ---------------------------------------------------------------------------
-- Table: estimate_sign_tokens
-- Customer-facing, single-use HMAC-signed URL tokens for e-sign flow.
-- Raw token is NEVER stored; only SHA-256(token) lives here.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS estimate_sign_tokens (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  estimate_id         INTEGER NOT NULL REFERENCES estimates(id) ON DELETE CASCADE,
  token_hash          TEXT    NOT NULL UNIQUE,
  expires_at          TEXT    NOT NULL,
  consumed_at         TEXT,
  created_by_user_id  INTEGER NOT NULL REFERENCES users(id),
  created_at          TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_estimate_sign_tokens_estimate_expires
  ON estimate_sign_tokens(estimate_id, expires_at);

-- ---------------------------------------------------------------------------
-- Table: estimate_signatures
-- Captured e-signature records (signer identity + SVG/PNG data URL).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS estimate_signatures (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  estimate_id         INTEGER NOT NULL REFERENCES estimates(id) ON DELETE CASCADE,
  signer_name         TEXT    NOT NULL,
  signer_email        TEXT,
  signer_ip           TEXT,
  signature_data_url  TEXT    NOT NULL,
  signed_at           TEXT    DEFAULT (datetime('now')),
  user_agent          TEXT
);

CREATE INDEX IF NOT EXISTS idx_estimate_signatures_estimate_id
  ON estimate_signatures(estimate_id);

-- ---------------------------------------------------------------------------
-- Table: data_export_schedules
-- Admin-configured recurring data export jobs.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS data_export_schedules (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  name                TEXT    NOT NULL,
  export_type         TEXT    NOT NULL CHECK(export_type IN ('full','customers','tickets','invoices','inventory','expenses')),
  interval_kind       TEXT    NOT NULL CHECK(interval_kind IN ('daily','weekly','monthly')),
  interval_count      INTEGER NOT NULL CHECK(interval_count > 0),
  next_run_at         TEXT    NOT NULL,
  last_run_at         TEXT,
  delivery_email      TEXT,
  status              TEXT    NOT NULL CHECK(status IN ('active','paused','canceled')) DEFAULT 'active',
  created_by_user_id  INTEGER NOT NULL REFERENCES users(id),
  created_at          TEXT    DEFAULT (datetime('now')),
  updated_at          TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_data_export_schedules_status_next_run
  ON data_export_schedules(status, next_run_at);

-- ---------------------------------------------------------------------------
-- Table: data_export_schedule_runs
-- Per-execution history for each schedule (for UI audit trail).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS data_export_schedule_runs (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  schedule_id     INTEGER REFERENCES data_export_schedules(id) ON DELETE CASCADE,
  run_at          TEXT    NOT NULL,
  succeeded       INTEGER NOT NULL,
  export_file     TEXT,
  error_message   TEXT
);

CREATE INDEX IF NOT EXISTS idx_data_export_schedule_runs_schedule_id
  ON data_export_schedule_runs(schedule_id);
