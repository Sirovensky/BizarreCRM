-- Migration 134: Sync Conflict Queue
-- SCAN-473: Mobile sync conflict resolution (android §20.3)
-- Lightweight conflict-queue + admin resolution endpoints.
-- Full sync engine (CRDT, vector clocks) is NOT implemented here.

-- ---------------------------------------------------------------------------
-- Table: sync_conflicts
-- One row per reported conflict from a mobile client. Conflicts are
-- DECLARATIVE — resolution records the chosen outcome; the client is
-- responsible for replaying the chosen version via the regular entity
-- endpoints (e.g. PUT /api/v1/tickets/:id). This table does NOT write
-- back to the entity table.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sync_conflicts (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,

  -- What conflicted
  entity_kind           TEXT    NOT NULL,           -- e.g. 'ticket', 'customer', 'invoice'
  entity_id             INTEGER NOT NULL,           -- PK in the target table (integer only)

  -- Conflict classification
  conflict_type         TEXT    NOT NULL
                                CHECK (conflict_type IN (
                                  'concurrent_update',
                                  'stale_write',
                                  'duplicate_create',
                                  'deleted_remote'
                                )),

  -- Opaque blobs — callers decide shape; server treats as plain text
  client_version_json   TEXT    NOT NULL,           -- client's copy at conflict time
  server_version_json   TEXT    NOT NULL,           -- server's authoritative copy at conflict time

  -- Reporter metadata (client-supplied device_id is NOT verified)
  reporter_user_id      INTEGER NOT NULL REFERENCES users(id),
  reporter_device_id    TEXT,                       -- client-supplied device identifier
  reporter_platform     TEXT
                                CHECK (reporter_platform IS NULL OR reporter_platform IN (
                                  'android', 'ios', 'web'
                                )),
  reported_at           TEXT    NOT NULL DEFAULT (datetime('now')),

  -- Queue lifecycle
  status                TEXT    NOT NULL DEFAULT 'pending'
                                CHECK (status IN ('pending','resolved','rejected','deferred')),

  -- Resolution (declarative — see note above)
  resolution            TEXT
                                CHECK (resolution IS NULL OR resolution IN (
                                  'keep_client', 'keep_server', 'merge', 'manual', 'rejected'
                                )),
  resolution_notes      TEXT,
  resolved_by_user_id   INTEGER REFERENCES users(id),
  resolved_at           TEXT
);

-- ---------------------------------------------------------------------------
-- Indices
-- ---------------------------------------------------------------------------

-- Primary queue view: pending items sorted by age
CREATE INDEX IF NOT EXISTS idx_sync_conflicts_status_reported
  ON sync_conflicts (status, reported_at DESC);

-- Look up all conflicts for a specific entity (e.g. all conflicts on ticket 42)
CREATE INDEX IF NOT EXISTS idx_sync_conflicts_entity
  ON sync_conflicts (entity_kind, entity_id);

-- Look up all conflicts reported by a user (audit / per-device analysis)
CREATE INDEX IF NOT EXISTS idx_sync_conflicts_reporter
  ON sync_conflicts (reporter_user_id);
