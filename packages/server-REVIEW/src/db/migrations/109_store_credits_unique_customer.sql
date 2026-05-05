-- ============================================================================
-- Migration 109 — UNIQUE constraint on store_credits(customer_id) (SEC-H67)
-- ============================================================================
--
-- Race condition: concurrent refund POSTs for the same customer both execute
-- the SELECT-then-INSERT/UPDATE pattern in refunds.routes.ts and can:
--   (a) both see zero rows → both INSERT → two rows per customer, or
--   (b) both SELECT the same row, then both UPDATE with non-atomic
--       read-modify-write → one credit increment is silently lost.
--
-- Fix in two parts:
--   1. This migration coalesces any existing duplicate store_credits rows
--      into a single row per customer (SUM of balances), then adds a UNIQUE
--      index that prevents duplicates from ever appearing again.
--   2. refunds.routes.ts is updated to use a single atomic
--      INSERT … ON CONFLICT(customer_id) DO UPDATE so that SQLite itself
--      ensures exactly-one-row-per-customer under any level of concurrency.
--
-- Idempotent: CREATE UNIQUE INDEX IF NOT EXISTS is safe to re-run.
-- The de-duplication CTE is also a no-op when no duplicates exist.
-- ============================================================================

-- Step 1: Coalesce duplicate rows.
--
-- We build an aggregate of (customer_id, summed amount, earliest created_at,
-- latest updated_at) for every customer that has MORE than one row, then
-- delete all their rows and insert the coalesced single row.
-- Everything runs inside the implicit migration transaction so it is atomic.

INSERT INTO store_credits (customer_id, amount, created_at, updated_at)
SELECT
    customer_id,
    SUM(amount)        AS amount,
    MIN(created_at)    AS created_at,
    MAX(updated_at)    AS updated_at
FROM store_credits
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- Remove the old (non-coalesced) rows for those customers.
-- The INSERT above already committed the new single-row aggregate, so we
-- delete any row whose id is NOT the max id for that customer (the one we
-- just inserted will always have the highest id).
DELETE FROM store_credits
WHERE id NOT IN (
    SELECT MAX(id)
    FROM store_credits
    GROUP BY customer_id
);

-- Step 2: Add the UNIQUE index so the race can never recur.
CREATE UNIQUE INDEX IF NOT EXISTS idx_store_credits_customer_unique
    ON store_credits(customer_id);
