-- SEC-M44: Track payment capture lifecycle so refunds can be gated to
-- actually-settled funds. Without this column the refund endpoint
-- (refunds.routes.ts) happily approved refunds against auth-only payments
-- that hadn't cleared — the shop would refund money that was never captured.
--
-- States:
--   'authorized' — payment row exists, card was authorized (hold placed) but
--                  funds have NOT posted. Refunds must reject.
--   'captured'   — funds settled. Refund is allowed.
--   'voided'     — the authorization was released before capture. No money
--                  ever moved, so there is nothing to refund either.
--
-- Current flows (BlockChyp / Stripe) capture immediately at charge time, so
-- every existing row is 'captured'. This migration adds the column with
-- DEFAULT 'captured' and backfills legacy rows to the same value, so behavior
-- is unchanged until the application code starts writing non-captured rows
-- (future auth-only terminal workflows).
--
-- Idempotent: PRAGMA table_info gate in the migration runner is not available,
-- so we use a guarded re-creation pattern. SQLite doesn't support IF NOT
-- EXISTS on ALTER TABLE ADD COLUMN, but this migration only runs once per DB
-- (tracked in _migrations), so a plain ALTER is safe.

ALTER TABLE payments
  ADD COLUMN capture_state TEXT NOT NULL DEFAULT 'captured'
    CHECK (capture_state IN ('authorized', 'captured', 'voided'));

-- Defensive backfill for the unlikely case where a prior column default
-- landed as NULL on some SQLite versions. All existing captured-immediately
-- payments stay 'captured' — that's the correct historical state.
UPDATE payments SET capture_state = 'captured' WHERE capture_state IS NULL;

CREATE INDEX IF NOT EXISTS idx_payments_capture_state ON payments(capture_state);
