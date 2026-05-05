-- §20 Offline / Sync & Caching foundation.
-- Adds sync_state (cursor pagination per §20.5) and expands sync_queue
-- to the shape the drain loop (§20.2) actually needs.

-- ── sync_state ────────────────────────────────────────────────────────────
-- One row per (entity, filter, parent_id) scope. Drives every list's
-- hasMore decision without touching `total_pages`.
CREATE TABLE IF NOT EXISTS sync_state (
    entity                TEXT    NOT NULL,
    filter_key            TEXT    NOT NULL DEFAULT '',
    parent_id             TEXT    NOT NULL DEFAULT '',
    cursor                TEXT,
    oldest_cached_at      TEXT,
    server_exhausted_at   TEXT,
    last_updated_at       TEXT,
    created_at            TEXT    NOT NULL,
    updated_at            TEXT    NOT NULL,
    PRIMARY KEY (entity, filter_key, parent_id)
);

CREATE INDEX IF NOT EXISTS idx_sync_state_entity ON sync_state(entity);

-- ── sync_queue (extend in place) ──────────────────────────────────────────
-- The initial migration created a minimal sync_queue. Drain loop needs
-- idempotency key + status machine + next_retry_at for backoff.
-- SQLite doesn't support ALTER COLUMN on NOT NULL constraints cleanly;
-- the safe path is: add nullable columns now, backfill defaults, enforce
-- at the app layer.

ALTER TABLE sync_queue ADD COLUMN op              TEXT;
ALTER TABLE sync_queue ADD COLUMN entity          TEXT;
ALTER TABLE sync_queue ADD COLUMN entity_local_id TEXT;
ALTER TABLE sync_queue ADD COLUMN entity_server_id TEXT;
ALTER TABLE sync_queue ADD COLUMN idempotency_key TEXT;
ALTER TABLE sync_queue ADD COLUMN status          TEXT NOT NULL DEFAULT 'queued';
ALTER TABLE sync_queue ADD COLUMN next_retry_at   TEXT;

-- Old `payload` column stays (holds JSON). Back-compat.
-- Fresh rows use: id, op, entity, entity_local_id, entity_server_id,
-- payload (JSON), idempotency_key, status, attempt_count, last_attempt,
-- last_error, next_retry_at, enqueued_at.

CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_queue_idempotency
    ON sync_queue(idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status);
CREATE INDEX IF NOT EXISTS idx_sync_queue_next_retry ON sync_queue(next_retry_at);
CREATE INDEX IF NOT EXISTS idx_sync_queue_entity ON sync_queue(entity);

-- ── sync_dead_letter ──────────────────────────────────────────────────────
-- §20.2 retries exhaust → tombstone record for manual retry / discard UI.
CREATE TABLE IF NOT EXISTS sync_dead_letter (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    op              TEXT    NOT NULL,
    entity          TEXT    NOT NULL,
    payload         TEXT    NOT NULL,
    idempotency_key TEXT,
    attempt_count   INTEGER NOT NULL,
    last_error      TEXT,
    first_attempted TEXT    NOT NULL,
    last_attempted  TEXT    NOT NULL,
    moved_at        TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sync_dead_letter_entity ON sync_dead_letter(entity);
