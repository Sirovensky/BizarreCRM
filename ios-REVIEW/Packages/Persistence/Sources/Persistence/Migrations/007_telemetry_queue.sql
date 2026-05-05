-- §32.0 Telemetry offline buffer.
-- Events are batched here when the device is offline and flushed to
-- POST /telemetry/events on reconnect via TelemetryFlushService.
-- All rows are passed through LogRedactor before insert; no raw PII is stored.

-- ── telemetry_queue ───────────────────────────────────────────────────────
-- Columns:
--   id            — UUID primary key (client-generated).
--   event_name    — dot-notation event identifier (e.g. "screen.viewed").
--   payload_json  — AnalyticsEventPayload JSON (redacted by LogRedactor).
--   session_id    — opaque per-session UUID; not a user identifier.
--   tenant_slug   — tenant context for routing on reconnect.
--   enqueued_at   — ISO-8601 UTC; used for oldest-first flush ordering.
--   status        — 'pending' | 'flushing' | 'done'.
--   attempt_count — number of flush attempts; rows with > 3 are dropped.

CREATE TABLE IF NOT EXISTS telemetry_queue (
    id            TEXT NOT NULL PRIMARY KEY,
    event_name    TEXT NOT NULL,
    payload_json  TEXT NOT NULL DEFAULT '{}',
    session_id    TEXT NOT NULL,
    tenant_slug   TEXT NOT NULL DEFAULT '',
    enqueued_at   TEXT NOT NULL,
    status        TEXT NOT NULL DEFAULT 'pending',
    attempt_count INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_telemetry_queue_status
    ON telemetry_queue(status, enqueued_at);

-- §32.0 backpressure: cap row count at 10 000 by deleting oldest on insert.
-- Enforced via app-layer guard in TelemetryFlushService (not a DB trigger to
-- avoid performance cost on every insert).
