-- ============================================================================
-- 118 — Fix payment trigger NULL guard (onboarding milestone)
-- ============================================================================
--
-- Problem:
--   Migration 115 created trg_onboarding_first_payment with this WHEN clause:
--
--     WHEN (SELECT order_id FROM invoices WHERE id = NEW.invoice_id)
--          NOT LIKE 'SAMPLE-%'
--
--   When invoice_id is NULL or the invoice row doesn't exist, the subquery
--   returns NULL. NULL NOT LIKE 'SAMPLE-%' evaluates to NULL (not TRUE), so
--   the trigger body silently never fires — first_payment_at is never stamped.
--
-- Fix:
--   Wrap the subquery in COALESCE so a missing invoice falls through as an
--   empty string, which correctly passes the NOT LIKE guard.
--
-- Note: DROP TRIGGER IF EXISTS + re-CREATE is safe on SQLite (no stored
-- procedures or dependent objects on triggers). The old trigger had never
-- actually fired in the NULL edge case, so no data is lost.
-- ----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_onboarding_first_payment;

CREATE TRIGGER IF NOT EXISTS trg_onboarding_first_payment
AFTER INSERT ON payments
WHEN COALESCE(
  (SELECT order_id FROM invoices WHERE id = NEW.invoice_id),
  ''
) NOT LIKE 'SAMPLE-%'
BEGIN
  UPDATE onboarding_state
    SET first_payment_at = datetime('now'),
        updated_at       = datetime('now')
    WHERE id = 1 AND first_payment_at IS NULL;
END;
