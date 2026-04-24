-- SCAN-1080: per-user audit tails were using idx_audit_logs_user then
-- sorting by created_at — every "last N audits for user X" page paid the
-- sort. A composite (user_id, created_at DESC) covers the common query
-- shape so SQLite walks the index in order and stops at LIMIT.
--
-- The old single-column idx_audit_logs_user is retained because other
-- queries (e.g. "count audits per user") still benefit from it, and
-- dropping it would make this migration harder to roll back on a live
-- deploy. SQLite will simply prefer the composite for prefix+sort reads.
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_created
  ON audit_logs (user_id, created_at DESC);
