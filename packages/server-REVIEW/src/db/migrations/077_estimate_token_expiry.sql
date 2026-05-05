-- SC4: Estimate approval token expiry + single-use tracking.
--
-- Previously, POST /estimates/:id/send generated an approval_token via
-- crypto.randomBytes(16) with no expiration and no single-use enforcement.
-- An attacker who obtained a token (shoulder surfing, SMS forwarding,
-- leaked log, etc.) could approve the estimate at any time in the future,
-- and could even replay the approval.
--
-- This migration adds:
--   - approval_token_expires_at: ISO timestamp (default = sent_at + 24h in app code)
--     After this, the token is rejected on POST /estimates/:id/approve.
--   - approval_token_used_at: ISO timestamp set when the token is consumed.
--     A non-null value means the token is spent and cannot be reused.
--
-- Both columns nullable TEXT — existing rows get NULL, which the approval
-- route treats as "legacy token with no expiry" (matches prior behavior)
-- to avoid breaking already-sent estimates. New tokens generated after this
-- migration always populate expires_at.
--
-- See estimates.routes.ts POST /:id/send and POST /:id/approve for
-- enforcement logic.

ALTER TABLE estimates ADD COLUMN approval_token_expires_at TEXT;
ALTER TABLE estimates ADD COLUMN approval_token_used_at TEXT;

CREATE INDEX IF NOT EXISTS idx_estimates_approval_token
    ON estimates(approval_token)
    WHERE approval_token IS NOT NULL;
