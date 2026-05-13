-- Migration 196 — WEB-UIUX-1208: track credit-note offsets separately from
-- real cash on `invoices.amount_paid`.
--
-- Pre-2026-05-12 the credit-note handler inflated `amount_paid` by the credit
-- value to drive `amount_due` to zero. A $100 invoice with $50 collected and
-- a $50 credit note ended up with `amount_paid=$100, status='paid'` — looks
-- paid in full even though the customer paid $50 cash and got a $50 ledger
-- offset. AR-vs-bank reconciliation silently disagrees by $50 forever.
--
-- The accountant-correct shape: `amount_paid` stays at the real cash
-- collected, a new `amount_credited` column carries the ledger offset, and
-- `amount_due = max(0, total - amount_paid - amount_credited)`. Combined
-- ledger reaches zero without lying about cash movement.
--
-- All pre-migration rows get back-filled to `amount_credited = SUM(credit_notes)`
-- so the new invariant holds for historical data too. The amount_paid figure
-- on those rows is NOT corrected — would require per-row reconstruction of
-- the original collection event and risks introducing fresh drift. Reports
-- that need true-cash on legacy rows should consult the `payments` table.
ALTER TABLE invoices ADD COLUMN amount_credited REAL NOT NULL DEFAULT 0;

-- Back-fill historical rows with the absolute total of their attached
-- credit-note invoices (the negative-invoice rows linked via credit_note_for).
UPDATE invoices
   SET amount_credited = COALESCE((
     SELECT SUM(ABS(cn.total))
       FROM invoices cn
      WHERE cn.credit_note_for = invoices.id
   ), 0)
 WHERE id IN (
   SELECT DISTINCT credit_note_for
     FROM invoices
    WHERE credit_note_for IS NOT NULL
 );
