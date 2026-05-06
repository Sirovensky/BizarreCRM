-- 167_user_permissions.sql
-- SEC-M61: per-user permission exceptions layered over ROLE_PERMISSIONS and
-- custom role_permissions. Rows are sparse overrides: allowed=1 grants,
-- allowed=0 denies, and no row inherits from the role matrix.

CREATE TABLE IF NOT EXISTS user_permissions (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  permission_key TEXT NOT NULL,
  allowed INTEGER NOT NULL CHECK (allowed IN (0, 1)),
  updated_by_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, permission_key)
);

CREATE INDEX IF NOT EXISTS idx_user_permissions_user
  ON user_permissions(user_id);

CREATE INDEX IF NOT EXISTS idx_user_permissions_key
  ON user_permissions(permission_key);
