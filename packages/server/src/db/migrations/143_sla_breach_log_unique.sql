-- SCAN-1056: SLA breach-log SELECT-then-INSERT has no DB-level uniqueness,
-- so two concurrent cron ticks on different workers could both pass the
-- existence check and double-insert. Add a UNIQUE index on
-- (ticket_id, breach_type) so the second INSERT fails (service layer
-- already wraps the insert in a try/catch and tolerates idempotency
-- conflicts via INSERT OR IGNORE — this migration lets that pattern
-- actually work).
CREATE UNIQUE INDEX IF NOT EXISTS ux_sla_breach_log_ticket_type
  ON sla_breach_log (ticket_id, breach_type);
