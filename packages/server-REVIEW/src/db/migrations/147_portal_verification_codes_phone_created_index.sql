-- SCAN-1170: migration 146 added (phone, used, expires_at) but the portal
-- verify handler reads `WHERE phone = ? AND used = 0 ORDER BY created_at
-- DESC LIMIT 1` — SQLite used the 146 index for the predicate but then
-- did an in-memory sort on every match. This composite adds created_at
-- as the trailing key so the walker stops at LIMIT 1 without sorting.
-- Kept separately from the 146 index because the expires_at suffix on
-- 146 is still useful for cron sweeps that read expired rows directly.
CREATE INDEX IF NOT EXISTS idx_portal_verify_phone_used_created
  ON portal_verification_codes (phone, used, created_at DESC);
