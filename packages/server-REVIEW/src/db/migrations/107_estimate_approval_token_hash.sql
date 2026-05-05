-- ============================================================================
-- Migration 107 — Estimate approval token SHA-256 hash at rest (SEC-H52)
-- ============================================================================
--
-- Previously, POST /estimates/:id/send stored `approval_token` as plaintext
-- in the `estimates` table (random hex from crypto.randomBytes). That means a
-- leaked DB dump hands an attacker every unexpired, unused approval token for
-- every pending estimate — they can silently mark each one "approved" before
-- the customer even opens the email/SMS. Since approval triggers downstream
-- side-effects (auto-ticket status transitions via SW-D7), the blast radius is
-- bigger than just the estimate row.
--
-- This migration adds `approval_token_hash TEXT` alongside the existing
-- `approval_token TEXT` column. Going forward:
--
--   * On /send: server generates a fresh token, stores ONLY the SHA-256 hash
--     (plus expiry + used_at), and emails/texts the plaintext. Plaintext
--     never lands in the DB.
--   * On /approve: server hashes the inbound token and looks up via
--     `approval_token_hash`. Constant-time compare prevents timing leaks.
--
-- Two-step rollover (matches the SEC-H38 gift-card pattern in migration 104):
--
--   Step 1 (this migration): add `approval_token_hash` column + index. Leave
--     plaintext `approval_token` in place so in-flight / pre-existing send
--     links don't break during the cutover. Backfill runs at boot via
--     `services/estimateApprovalTokenHashBackfill.ts` (SQLite has no sha256).
--   Step 2 (follow-up migration, not yet scheduled): drop the plaintext
--     `approval_token` column once all outstanding tokens have either been
--     used, expired, or re-sent with the hash-only flow.
--
-- The verify endpoint prefers the hash lookup; if no row matches and legacy
-- `approval_token` column is still populated for that estimate, it falls back
-- once, populates the hash, and nulls the plaintext (hash-migrate on first
-- verify). After grace period + migration 107b, the fallback goes away.
-- ============================================================================

ALTER TABLE estimates ADD COLUMN approval_token_hash TEXT;

CREATE INDEX IF NOT EXISTS idx_estimates_approval_token_hash
    ON estimates(approval_token_hash)
    WHERE approval_token_hash IS NOT NULL;
