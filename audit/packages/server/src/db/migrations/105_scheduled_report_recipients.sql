-- SEC-M47: move scheduled-report recipients from a single
-- `store_config.scheduled_report_email` string into a first-class
-- table with per-recipient send status + audit trail. The string
-- column is kept as a fallback for existing deployments (the
-- services/scheduledReports.ts sender now reads the table first
-- and falls back to the config string).
--
-- Schema mirrors a typical email-queue:
--   - email UNIQUE per tenant (one row per address; tenant scoping
--     is DB-level via the per-tenant file, so no explicit tenant
--     column is needed)
--   - status: enabled/disabled toggle per address (owner can silence
--     one recipient without removing the row)
--   - last_sent_at / last_status / last_error give ops visibility
--     into whether the nightly cron actually delivered
--
-- Migration is additive — no backfill from store_config because the
-- cron's first successful run will record last_sent_at against
-- whatever addresses exist in both stores.

CREATE TABLE IF NOT EXISTS scheduled_report_recipients (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  email        TEXT NOT NULL UNIQUE,
  enabled      INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  last_sent_at TEXT,
  last_status  TEXT CHECK (last_status IS NULL OR last_status IN ('success','failed','skipped')),
  last_error   TEXT,
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_scheduled_report_recipients_enabled
  ON scheduled_report_recipients(enabled);
