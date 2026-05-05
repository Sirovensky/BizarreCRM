-- ============================================================================
-- Migration 108 — PII retention defaults + ticket_notes redaction columns (SEC-H57)
-- ============================================================================
--
-- Audit issue P3-PII-08: SMS threads, call logs, email history, and ticket
-- notes grow forever. Under GDPR / CCPA / most US state privacy regimes you
-- cannot retain customer communications indefinitely without a stated purpose.
-- 24 months is the conservative industry default for small-business CRM
-- comms and matches what RepairDesk / Shopify / Square default to.
--
-- This migration does two things:
--
-- 1. Adds `redacted_at` + `redacted_by` columns to `ticket_notes`. Unlike
--    sms_messages / call_logs / email_messages (where the whole row is the
--    log entry and a pure DELETE is acceptable), ticket_notes rows are the
--    audit trail of tech decisions on a ticket — we keep the row for FK
--    integrity (parent_id self-reference) + audit, but blank the body once
--    the content passes its retention window. `redacted_by` is nullable
--    because the sweep runs as a system cron, not a user.
--
-- 2. Seeds four `store_config` retention knobs at the 24-month default.
--    Tenants can override any of them via the settings UI. The sweeper
--    reads these at run time — missing keys fall back to 24mo, so older
--    tenants that migrate up don't need a data backfill.
--
--    * retention_sms_months           — sms_messages DELETE cutoff
--    * retention_calls_months         — call_logs DELETE cutoff
--    * retention_email_months         — email_messages DELETE cutoff
--    * retention_ticket_notes_months  — ticket_notes redact cutoff
--
-- Audit breadcrumbs: for each non-zero batch the sweeper writes one
-- `audit_logs` row with event `retention_sweep_pii` and a JSON summary
-- (table + rows_affected + cutoff). That gives compliance a paper trail
-- without a row-per-deleted-row explosion.
-- ============================================================================

ALTER TABLE ticket_notes ADD COLUMN redacted_at TEXT;
ALTER TABLE ticket_notes ADD COLUMN redacted_by INTEGER REFERENCES users(id);

-- Partial index so the sweeper can cheaply find un-redacted rows past the
-- cutoff without scanning the whole table. `redacted_at IS NULL` keeps the
-- index tiny (once rows are redacted they stay redacted forever).
CREATE INDEX IF NOT EXISTS idx_ticket_notes_redaction_pending
    ON ticket_notes(created_at)
    WHERE redacted_at IS NULL;

INSERT OR IGNORE INTO store_config (key, value) VALUES ('retention_sms_months', '24');
INSERT OR IGNORE INTO store_config (key, value) VALUES ('retention_calls_months', '24');
INSERT OR IGNORE INTO store_config (key, value) VALUES ('retention_email_months', '24');
INSERT OR IGNORE INTO store_config (key, value) VALUES ('retention_ticket_notes_months', '24');
