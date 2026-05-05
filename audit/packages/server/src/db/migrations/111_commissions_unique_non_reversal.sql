-- ============================================================================
-- Migration 111 — UNIQUE partial index on commissions(ticket_id)
--                 WHERE type != 'reversal'  (SEC-H68)
-- ============================================================================
--
-- Race condition: concurrent ticket status-change calls (one from a human PATCH,
-- one from an automation, or two racing automations) can both pass the
-- "is this ticket now completed?" pre-check SELECT in ticketStatus.ts before
-- either INSERT commits, resulting in two non-reversal commission rows for the
-- same ticket_id — paying the technician twice.
--
-- Fix in two parts:
--   1. This migration adds a UNIQUE partial index covering only the rows where
--      type != 'reversal' and ticket_id IS NOT NULL.  Reversal rows are excluded
--      so a ticket can accumulate: one forward commission row + N reversal rows
--      (e.g. one per partial-refund event). Historical records are untouched.
--   2. ticketStatus.ts wraps the commission INSERT (via writeCommission) in a
--      try/catch that recognises SQLITE_CONSTRAINT_UNIQUE and logs at info level
--      rather than re-throwing, so the racing second call becomes a benign
--      no-op.  The pre-check SELECT remains as a fast path but is no longer the
--      correctness guarantee.
--
-- Pre-existing duplicates:
--   We never delete tenant data (see CLAUDE.md). The SELECT below will appear
--   in migration output and alert the operator if duplicates already exist.
--   If duplicates are present, the CREATE UNIQUE INDEX below will FAIL and the
--   migration will roll back.  The operator must manually resolve the duplicate
--   rows (e.g. keep the earliest commission per ticket and delete the extras)
--   before re-running migrations.
--
-- Idempotent: CREATE UNIQUE INDEX IF NOT EXISTS is safe to re-run.
-- ============================================================================

-- Diagnostic: list any ticket_ids that already have more than one non-reversal
-- commission row. Zero rows means we are clean. Non-zero rows block the index
-- creation below until the operator resolves the duplicates manually.
SELECT
    ticket_id,
    COUNT(*)           AS non_reversal_count,
    GROUP_CONCAT(id)   AS commission_ids
FROM commissions
WHERE COALESCE(type, '') != 'reversal'
  AND ticket_id IS NOT NULL
GROUP BY ticket_id
HAVING COUNT(*) > 1;

-- Add the partial UNIQUE index.
-- If the SELECT above returned any rows the operator MUST remove the duplicate
-- non-reversal commission rows before this line will succeed.
-- No data is deleted automatically.
CREATE UNIQUE INDEX IF NOT EXISTS idx_commissions_non_reversal_unique
    ON commissions(ticket_id)
    WHERE type != 'reversal';
