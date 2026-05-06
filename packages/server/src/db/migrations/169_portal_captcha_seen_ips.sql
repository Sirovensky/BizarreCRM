-- SEC-M21-captcha: remember portal registration IPs that have solved CAPTCHA.
CREATE TABLE IF NOT EXISTS portal_captcha_seen_ips (
  ip_hash TEXT PRIMARY KEY,
  provider TEXT NOT NULL,
  first_seen_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_portal_captcha_seen_ips_expires
  ON portal_captcha_seen_ips (expires_at);
