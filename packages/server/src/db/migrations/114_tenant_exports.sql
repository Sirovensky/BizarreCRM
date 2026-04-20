-- SEC-H59 / P3-PII-16: Full tenant export for data portability.
-- Tracks async export jobs: status, encrypted file location, single-use
-- signed download token, and 7-day retention enforcement.
--
-- Design notes:
--   * download_token is UNIQUE so a collision (astronomically unlikely for 32
--     random bytes) is caught at DB level, not silently overwritten.
--   * downloaded_at enforces single-use: once set, the download handler
--     rejects any subsequent request for the same token.
--   * download_token_expires_at is an ISO-8601 string (SQLite has no native
--     DATETIME type); comparisons done with datetime() in queries.
--   * tenant_id references tenants.id in multi-tenant mode; in single-tenant
--     mode the column is set to 0 (a sentinel) so the schema stays universal.

CREATE TABLE IF NOT EXISTS tenant_exports (
  id                        INTEGER PRIMARY KEY AUTOINCREMENT,
  tenant_id                 INTEGER NOT NULL,
  requested_by_user_id      INTEGER NOT NULL,
  status                    TEXT    NOT NULL DEFAULT 'pending'
                                    CHECK (status IN ('pending','running','complete','failed')),
  started_at                TEXT    NOT NULL DEFAULT (datetime('now')),
  completed_at              TEXT,
  file_path                 TEXT,
  byte_size                 INTEGER,
  error_message             TEXT,
  download_token            TEXT    UNIQUE,
  download_token_expires_at TEXT,
  downloaded_at             TEXT
);

CREATE INDEX IF NOT EXISTS idx_tenant_exports_tenant
  ON tenant_exports(tenant_id);

CREATE INDEX IF NOT EXISTS idx_tenant_exports_status
  ON tenant_exports(status);

CREATE INDEX IF NOT EXISTS idx_tenant_exports_token
  ON tenant_exports(download_token)
  WHERE download_token IS NOT NULL;
