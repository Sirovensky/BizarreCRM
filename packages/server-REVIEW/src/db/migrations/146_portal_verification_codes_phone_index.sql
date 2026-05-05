-- SCAN-1165: the portal_verification_codes table was created in migration
-- 041 with only a `customer_id` index. The signup-verify hot path at
-- `portal.routes.ts:869,877` filters by `phone + used + expires_at` which
-- had no covering index — every verify request scanned the full table.
-- Composite index covers the common "find an unused, non-expired code
-- for this phone" shape plus the ORDER BY created_at DESC that the
-- handler uses to pick the newest candidate.
CREATE INDEX IF NOT EXISTS idx_portal_verify_phone_used_expires
  ON portal_verification_codes (phone, used, expires_at);
