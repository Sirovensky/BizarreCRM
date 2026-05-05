-- Import locks + per-tenant import rate limits
--
-- Context (audit sections 12/R1 and 23/PL3):
--
--   R1 (CRITICAL) — import.routes.ts#POST /repairdesk/start used an advisory
--       "SELECT ... WHERE status IN ('running','pending')" check before
--       inserting new import_runs rows. Two concurrent POSTs both passed the
--       guard and both kicked off parallel background imports, hammering the
--       external RepairDesk API and racing each other's writes. Classic
--       TOCTOU.
--
--       Fix: this migration adds a singleton import_locks table with a
--       single-row CHECK(id=1) constraint. Starting an import is an atomic
--       INSERT (or conditional UPDATE) that claims the lock in one SQL
--       statement — the second concurrent POST's INSERT either hits the
--       CHECK(id=1) or a non-null holder field and fails fast. The lock is
--       released by the import's completion handler or by a TTL sweep.
--
--   PL3 (CRITICAL) — import.routes.ts#POST /repairdesk/start had no per-tenant
--       throttle. A Free-tier admin could loop import runs and burn through
--       the shop's RepairDesk quota or generate unbounded load. Plan
--       enforcement (PLAN_DEFINITIONS) was also absent.
--
--       Fix: import_rate_limits is a simple counter table keyed by
--       (category, window_start). The import route enforces:
--           - max 1 import in any rolling 5 minute window
--           - max 10 imports in any rolling 24 hour window
--       Both windows are checked in application code before the lock claim.
--       Because the limits are a ceiling on *run starts* (not records
--       imported), big quota imports are still allowed — we just prevent
--       abusive thrashing.
--
-- Both tables live in the tenant DB because imports are per-tenant.

-- ---------------------------------------------------------------------------
-- Singleton import lock. Exactly one row may ever exist (id=1). holder_id is
-- the import_runs.id that currently owns the lock. When no import is active
-- the row is either absent entirely (first ever claim) or holder_id is NULL.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS import_locks (
  id         INTEGER PRIMARY KEY CHECK (id = 1),
  holder_id  INTEGER,                          -- import_runs.id (or batch seed id) that owns the lock; NULL = free
  source     TEXT,                             -- 'repairdesk' | 'repairshopr' | 'myrepairapp'
  claimed_at TEXT,                             -- ISO-8601 when lock was acquired
  expires_at TEXT                              -- ISO-8601 when the lock auto-releases (TTL guard)
);

-- Pre-seed the row with holder_id = NULL so subsequent claim attempts can use
-- a conditional UPDATE (atomic) rather than an INSERT OR IGNORE race.
INSERT OR IGNORE INTO import_locks (id, holder_id, source, claimed_at, expires_at)
VALUES (1, NULL, NULL, NULL, NULL);

-- ---------------------------------------------------------------------------
-- Per-tenant import rate limit counters. Simple "sliding window via logged
-- timestamps" — on each import-start attempt the route deletes rows older
-- than the longest window (24h) then counts remaining rows to decide whether
-- to allow the start. One row per successful claim.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS import_rate_limits (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  source       TEXT NOT NULL,                   -- 'repairdesk' | 'repairshopr' | 'myrepairapp'
  started_at   TEXT NOT NULL DEFAULT (datetime('now')),
  user_id      INTEGER,                         -- who started it (from req.user.id)
  ip_address   TEXT                             -- source IP for audit
);

CREATE INDEX IF NOT EXISTS idx_import_rate_limits_started_at
  ON import_rate_limits(started_at);
CREATE INDEX IF NOT EXISTS idx_import_rate_limits_source_started
  ON import_rate_limits(source, started_at);
