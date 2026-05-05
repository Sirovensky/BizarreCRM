-- Migration 073: Password history + session idle tracking
-- Addresses critical audit items:
--   A7: Soft cap on concurrent sessions per user (5 active sessions, oldest pruned).
--       Existing `sessions` table from 001_initial already suffices as the refresh-token
--       store, so this migration only adds a last_active column + index needed for A8.
--   A8: Idle-session timeout — middleware rejects sessions whose last_active is > 14d old.
--   P2FA8: Password history check — reject new passwords that match the last 5 used.
--
-- Non-destructive. Safe to re-run (IF NOT EXISTS guards + ALTER with try/catch semantics
-- handled by migration runner).

-- ---------------------------------------------------------------------------
-- 1. Sessions idle-tracking column
-- ---------------------------------------------------------------------------
-- SQLite disallows non-constant DEFAULT on ALTER TABLE ADD COLUMN, so the
-- column has no default; new rows set it explicitly on INSERT, existing rows
-- are back-filled once at migration time.
ALTER TABLE sessions ADD COLUMN last_active TEXT;
UPDATE sessions SET last_active = COALESCE(created_at, datetime('now')) WHERE last_active IS NULL;

CREATE INDEX IF NOT EXISTS idx_sessions_last_active ON sessions(last_active);

-- Compound index that makes "active sessions per user, oldest first" fast for A7 pruning.
CREATE INDEX IF NOT EXISTS idx_sessions_user_created ON sessions(user_id, created_at);

-- ---------------------------------------------------------------------------
-- 2. Password history table
-- ---------------------------------------------------------------------------
-- Stores a bcrypt hash per historical password. On password change we compare
-- the new plaintext against the last 5 hashes using bcrypt.compareSync; reject
-- the change if any match. Oldest rows are pruned to keep exactly 5 per user.
CREATE TABLE IF NOT EXISTS password_history (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  password_hash TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_password_history_user_created
  ON password_history(user_id, created_at DESC);
