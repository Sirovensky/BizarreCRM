-- L7: Outbound webhook dead-letter queue
--
-- services/webhooks.ts#fireWebhook() was a pure fire-and-forget POST with a 5s
-- timeout. If the remote endpoint returned 5xx, timed out, or dropped the
-- connection, the error was logged to stdout and silently discarded. There was
-- no retry, no dead-letter queue, and no way for the shop owner to see that
-- notifications to their downstream system were failing.
--
-- Fix: webhooks.ts now retries with exponential backoff (attempts at 0s, 2s,
-- 8s) and if the final attempt still fails, inserts a row into this table
-- so the failure is durable and visible via a future admin UI / query.
--
-- Schema notes:
--   endpoint        — the webhook URL at the time of the failed delivery
--                     (stored because store_config.webhook_url may be rotated
--                     later and we want an accurate audit trail)
--   event           — the WebhookEvent string (ticket_created etc.)
--   payload         — the full JSON body we attempted to send, as TEXT
--   attempts        — how many POST attempts we actually made before giving up
--   last_error      — the error message from the final attempt
--   last_status     — HTTP status code of the final attempt, or NULL for
--                     network / timeout errors that never reached a response
--   created_at      — when the row was written (i.e. when we gave up)

CREATE TABLE IF NOT EXISTS webhook_delivery_failures (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  endpoint    TEXT NOT NULL,
  event       TEXT NOT NULL,
  payload     TEXT NOT NULL,
  attempts    INTEGER NOT NULL DEFAULT 0,
  last_error  TEXT,
  last_status INTEGER,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_webhook_delivery_failures_event
  ON webhook_delivery_failures(event);
CREATE INDEX IF NOT EXISTS idx_webhook_delivery_failures_created_at
  ON webhook_delivery_failures(created_at);
