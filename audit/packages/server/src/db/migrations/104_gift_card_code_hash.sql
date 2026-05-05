-- ============================================================================
-- Migration 104 — Gift card code SHA-256 hash (SEC-H38)
-- ============================================================================
--
-- Stores a SHA-256 hash of each gift card code alongside the existing
-- plaintext `code` column. Lookups switch to comparing the hash, so the
-- plaintext is no longer an enumeration primitive at rest.
--
-- Two-step rollover:
--   Step 1 (this migration): add `code_hash` column + index. Plaintext
--     `code` stays to let pre-existing redemption scripts keep running
--     during the cutover.
--   Step 2 (follow-up migration, not yet scheduled): drop the plaintext
--     `code` column once all redemption paths are hash-first.
--
-- SQLite has no built-in sha256 function, so the backfill runs in a tiny
-- Node helper at startup (see `services/giftCardCodeHashBackfill.ts`).
-- That helper is idempotent — it only updates rows where `code_hash IS
-- NULL`, so a repeated boot is a no-op.
-- ============================================================================

ALTER TABLE gift_cards ADD COLUMN code_hash TEXT;

CREATE INDEX IF NOT EXISTS idx_gift_cards_code_hash
  ON gift_cards(code_hash);
