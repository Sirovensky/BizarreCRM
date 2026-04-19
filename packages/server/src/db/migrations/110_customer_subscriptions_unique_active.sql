-- ============================================================================
-- Migration 110 — UNIQUE partial index on customer_subscriptions(customer_id)
--                 WHERE status IN ('active', 'past_due')  (SEC-H72)
-- ============================================================================
--
-- Race condition: concurrent POST /subscribe requests for the same customer_id
-- both pass the SELECT "is there already an active sub?" pre-check before
-- either INSERT commits, resulting in two rows with status='active' for the
-- same customer — causing a double billing cycle and an un-cancellable state.
--
-- Fix in two parts:
--   1. This migration adds a UNIQUE partial index covering only the rows
--      where status IN ('active', 'past_due').  Cancelled/paused subscriptions
--      are excluded so historical records remain intact.
--   2. membership.routes.ts is updated to remove the now-redundant pre-check
--      SELECT and to catch the SQLITE_CONSTRAINT_UNIQUE error from a racing
--      concurrent INSERT, returning 409 Conflict instead of 500.
--
-- Pre-existing duplicates:
--   We never delete tenant data (see CLAUDE.md). The SELECT below will appear
--   in migration output and alert the operator if duplicates already exist.
--   If duplicates are present, the CREATE UNIQUE INDEX below will FAIL and
--   the migration will roll back.  The operator must manually resolve the
--   duplicate rows (e.g. cancel all but the most recent active sub per
--   customer) before re-running migrations.
--
-- Idempotent: CREATE UNIQUE INDEX IF NOT EXISTS is safe to re-run.
-- ============================================================================

-- Diagnostic: list any customers who already have more than one live sub.
-- This SELECT produces rows in the migration output; zero rows means we are clean.
SELECT
    customer_id,
    COUNT(*) AS live_sub_count,
    GROUP_CONCAT(id) AS subscription_ids
FROM customer_subscriptions
WHERE status IN ('active', 'past_due')
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- Add the partial UNIQUE index.
-- If the SELECT above returned any rows the operator MUST cancel the extras
-- before this line will succeed.  No data is deleted automatically.
CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_subscriptions_active_unique
    ON customer_subscriptions(customer_id)
    WHERE status IN ('active', 'past_due');
