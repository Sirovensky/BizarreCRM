-- Setup tokens for tenant admin email verification + first-time password setup.
--
-- Context (audit section 34, TP3/TP4):
--   Previously the setup token was stored in plaintext inside store_config with
--   no consumption check and no expiry enforcement, so any tenant admin who
--   could read store_config saw a forever-valid bootstrap token. This table
--   replaces that: we store only the sha256 hash of the token, enforce the
--   24h expiry via expires_at, and mark single-use via consumed_at.
--
-- Flow:
--   1. provisionTenant() generates a random token, stores sha256(token) here,
--      and returns the RAW token to the caller exactly once.
--   2. The caller emails the setup URL to the admin. The token is never
--      persisted in store_config or anywhere else.
--   3. When the admin clicks the link, the consumer route looks up by
--      token_hash, verifies expires_at > now() AND consumed_at IS NULL,
--      then sets consumed_at and activates the admin user (password_set=1).
--   4. Re-use is blocked by the consumed_at IS NULL check.
--
-- This table lives in each tenant DB because the setup flow is per-tenant and
-- the tenant DB is the source of truth for the admin user.
CREATE TABLE IF NOT EXISTS setup_tokens (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  tenant_id   INTEGER,                      -- master DB tenants.id (nullable: no FK possible cross-DB)
  token_hash  TEXT NOT NULL UNIQUE,         -- sha256(token) hex
  expires_at  TEXT NOT NULL,                -- ISO-8601 expiry, enforced by consumer
  consumed_at TEXT,                         -- ISO-8601 consumption time; NULL = still valid
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Primary lookup: find a token by hash during consumption.
CREATE INDEX IF NOT EXISTS idx_setup_tokens_hash    ON setup_tokens(token_hash);
-- Admin housekeeping: find expired-but-not-consumed tokens for cleanup.
CREATE INDEX IF NOT EXISTS idx_setup_tokens_expires ON setup_tokens(expires_at);
