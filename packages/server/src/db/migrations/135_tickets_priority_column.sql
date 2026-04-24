-- Migration 135: add priority column to tickets and supporting SLA index
--
-- NOT NULL DEFAULT 'normal' backfills every existing row to 'normal' safely.
-- The CHECK constraint enforces the enum at the DB layer; routes enforce it too.

ALTER TABLE tickets
  ADD COLUMN priority TEXT NOT NULL DEFAULT 'normal'
  CHECK(priority IN ('low', 'normal', 'high', 'critical'));

CREATE INDEX IF NOT EXISTS idx_tickets_priority_sla
  ON tickets(priority, sla_breached);
