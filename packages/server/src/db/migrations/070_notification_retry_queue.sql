-- Notification retry queue: holds failed SMS sends for exponential-backoff retry.
-- Referenced by services/notifications.ts via enqueueRetry() and processRetryQueue().
-- Every tenant DB needs this table; the retry cron (index.ts forEachDbAsync) walks
-- all active tenants and calls processRetryQueue() every minute.
--
-- This table was originally missing from migrations entirely — processRetryQueue()
-- failed on every run with "no such table: notification_retry_queue" for every tenant.
CREATE TABLE IF NOT EXISTS notification_retry_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  recipient_phone TEXT NOT NULL,
  message TEXT NOT NULL,
  entity_type TEXT,                                 -- 'ticket', 'invoice', etc (nullable)
  entity_id INTEGER,                                -- related record ID (nullable)
  tenant_slug TEXT,                                 -- multi-tenant context (nullable in single-tenant)
  retry_count INTEGER NOT NULL DEFAULT 0,
  max_retries INTEGER NOT NULL DEFAULT 3,
  next_retry_at TEXT NOT NULL,
  last_error TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- processRetryQueue() orders by next_retry_at ASC and filters retry_count < max_retries,
-- so a composite index on (next_retry_at, retry_count) would help the hot path.
CREATE INDEX IF NOT EXISTS idx_nrq_next_retry ON notification_retry_queue(next_retry_at);
CREATE INDEX IF NOT EXISTS idx_nrq_retry_count ON notification_retry_queue(retry_count);
