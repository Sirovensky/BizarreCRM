-- Persistent rate limiting table (replaces in-memory Maps that reset on restart)
-- Covers: login attempts (IP + username), TOTP 2FA attempts, PIN switch-user attempts
CREATE TABLE IF NOT EXISTS rate_limits (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  category TEXT NOT NULL,       -- 'login_ip', 'login_user', 'totp', 'pin'
  key TEXT NOT NULL,            -- IP address, tenantSlug:username, tenantSlug:userId
  count INTEGER NOT NULL DEFAULT 0,
  first_attempt INTEGER NOT NULL, -- epoch ms
  locked_until INTEGER,           -- epoch ms (for TOTP lockout-style limiting)
  UNIQUE(category, key)
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_category_key ON rate_limits(category, key);
CREATE INDEX IF NOT EXISTS idx_rate_limits_first_attempt ON rate_limits(first_attempt);
