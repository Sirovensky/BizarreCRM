-- ============================================================================
-- Migration 119 — UNIQUE partial index on commissions(invoice_id)
--                 WHERE type != 'reversal'  (companion to migration 111)
-- ============================================================================
--
-- Bug: Migration 111 added a UNIQUE partial index on commissions(ticket_id)
-- to prevent double-commission on concurrent ticket closes, but did NOT add
-- the equivalent guard for invoice_id. Two concurrent payment requests on the
-- same invoice both pass the pre-check SELECT before either INSERT commits,
-- resulting in two non-reversal commission rows for the same invoice_id when
-- commission_type is percent_ticket or percent_service.
--
-- The flat_per_ticket path already has an application-level idempotency check,
-- but all commission types now benefit from this DB-level uniqueness guard.
--
-- Diagnostic: list invoice_ids with duplicate non-reversal commission rows.
-- Zero rows means we are clean. Non-zero rows will block the index below.
SELECT
    invoice_id,
    COUNT(*)           AS non_reversal_count,
    GROUP_CONCAT(id)   AS commission_ids
FROM commissions
WHERE COALESCE(type, '') != 'reversal'
  AND invoice_id IS NOT NULL
GROUP BY invoice_id
HAVING COUNT(*) > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_commissions_invoice_non_reversal_unique
    ON commissions(invoice_id)
    WHERE type != 'reversal'
      AND invoice_id IS NOT NULL;
