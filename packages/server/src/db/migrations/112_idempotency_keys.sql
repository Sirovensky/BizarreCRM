-- ============================================================================
-- Migration 112 — idempotency_keys table  (SEC-H71)
-- ============================================================================
--
-- Problem: the idempotency middleware previously kept results in an in-memory
-- Map, which meant:
--   (a) a process restart silently wiped all stored keys, so a retried POST
--       arriving after a restart would re-execute and potentially double-bill;
--   (b) in a multi-process deploy every process had its own Map, so the
--       key-reuse check did not work across process boundaries.
--
-- Fix: move the store into a per-tenant SQLite table.  Because `req.db` is
-- already the tenant DB, the table lives per-tenant automatically — no
-- cross-tenant data mixing is possible.
--
-- Key design decisions:
--   * UNIQUE(user_id, key) — enforced by the DB engine; a racing second INSERT
--     for the same (user_id, key) pair gets SQLITE_CONSTRAINT_UNIQUE, which the
--     middleware converts to a 409 "already in progress" response.
--   * request_hash — SHA-256 of (method + path + body) lets the middleware
--     detect when a retry sends a different body under the same key (422).
--   * response_status / response_body — stored after the first request
--     completes so exact replays are returned verbatim.
--   * response_status IS NULL while the first request is still in-flight.
--   * idx_idempotency_keys_created — supports the 24-hour TTL sweep that
--     deletes old rows via retentionSweeper (RULES array).
--
-- Idempotent: CREATE TABLE/INDEX IF NOT EXISTS is safe to re-run.
-- ============================================================================

CREATE TABLE IF NOT EXISTS idempotency_keys (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id         INTEGER NOT NULL,
  key             TEXT    NOT NULL,
  request_hash    TEXT,                    -- SHA-256 of (method + path + body) for mismatch detection
  response_status INTEGER,                 -- HTTP status of the first response (NULL while in-flight)
  response_body   TEXT,                    -- JSON blob of the first response (capped at ~64 KB in middleware)
  created_at      TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_id, key)
);

CREATE INDEX IF NOT EXISTS idx_idempotency_keys_created
    ON idempotency_keys(created_at);
