-- @no-transaction
-- Migration 138: FK ON DELETE cascade / SET NULL hardening
-- SCAN-508: ops_checklist_instances.template_id → ON DELETE SET NULL (column becomes nullable)
-- SCAN-509: tickets.sla_policy_id             → ON DELETE SET NULL via TRIGGER (safe alt, no table rebuild)
-- SCAN-510: field_service_jobs.customer_id    → ON DELETE SET NULL
-- SCAN-517: sync_conflicts.resolved_by_user_id→ ON DELETE SET NULL
-- SCAN-518: pl_snapshots.generated_by_user_id → ON DELETE SET NULL
--
-- This migration uses `PRAGMA foreign_keys = OFF` + an explicit BEGIN /
-- COMMIT block because PRAGMA foreign_keys cannot be toggled inside an
-- active transaction. The @no-transaction directive tells migrate.ts to
-- skip its outer transaction wrapper; the explicit BEGIN/COMMIT inside
-- this file owns transactional boundaries.
--
-- SQLite cannot modify FK clauses via ALTER TABLE — table rebuild is required.
-- EXCEPTION — tickets.sla_policy_id (SCAN-509): the tickets table is very large
-- with many columns, FTS triggers, and existing indices. A full table rebuild
-- on production data carries unacceptable risk of data loss if the schema
-- drifts from what is recorded here. Instead we install an AFTER DELETE
-- trigger on sla_policies that NULLs the four SLA columns on tickets,
-- achieving identical SET NULL semantics without touching the table DDL.

PRAGMA foreign_keys = OFF;

BEGIN TRANSACTION;

-- ===========================================================================
-- SCAN-508: ops_checklist_instances — template_id becomes nullable, ON DELETE SET NULL
-- Original DDL from migration 128 (tables renamed to ops_* to avoid collision
-- with the per-device `checklist_templates` table created by migration 001).
-- Existing indices:
--   idx_ops_checklist_instances_owner_started   (completed_by_user_id, started_at)
--   idx_ops_checklist_instances_template_completed (template_id, completed_at)
-- ===========================================================================

ALTER TABLE ops_checklist_instances RENAME TO ops_checklist_instances_old;

CREATE TABLE ops_checklist_instances (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  template_id           INTEGER     REFERENCES ops_checklist_templates(id) ON DELETE SET NULL,
  completed_by_user_id  INTEGER NOT NULL REFERENCES users(id),
  completed_items_json  TEXT    NOT NULL DEFAULT '[]',
  notes                 TEXT,
  status                TEXT    NOT NULL DEFAULT 'in_progress'
                                CHECK (status IN ('in_progress','completed','abandoned')),
  started_at            TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now')),
  completed_at          TEXT
);

INSERT INTO ops_checklist_instances
  SELECT
    id,
    template_id,
    completed_by_user_id,
    completed_items_json,
    notes,
    status,
    started_at,
    completed_at
  FROM ops_checklist_instances_old;

DROP TABLE ops_checklist_instances_old;

CREATE INDEX IF NOT EXISTS idx_ops_checklist_instances_owner_started
  ON ops_checklist_instances (completed_by_user_id, started_at);

CREATE INDEX IF NOT EXISTS idx_ops_checklist_instances_template_completed
  ON ops_checklist_instances (template_id, completed_at);

-- ===========================================================================
-- SCAN-509: tickets.sla_policy_id — trigger-based SET NULL (no table rebuild)
-- Trigger fires AFTER a sla_policies row is deleted and NULLs all four
-- SLA columns on any tickets that referenced that policy.
-- ===========================================================================

DROP TRIGGER IF EXISTS trg_sla_policies_delete_set_null;

CREATE TRIGGER trg_sla_policies_delete_set_null
  AFTER DELETE ON sla_policies
  FOR EACH ROW
BEGIN
  UPDATE tickets
  SET
    sla_policy_id            = NULL,
    sla_first_response_due_at = NULL,
    sla_resolution_due_at    = NULL,
    sla_breached             = 0
  WHERE sla_policy_id = OLD.id;
END;

-- ===========================================================================
-- SCAN-510: field_service_jobs — customer_id gets ON DELETE SET NULL
-- Original DDL from migration 130.
-- Existing indices:
--   idx_fsj_status_window  (status, scheduled_window_start)
--   idx_fsj_tech_status    (assigned_technician_id, status)
--   idx_fsj_latlng         (lat, lng)
-- ===========================================================================

ALTER TABLE field_service_jobs RENAME TO field_service_jobs_old;

CREATE TABLE field_service_jobs (
  id                          INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id                   INTEGER REFERENCES tickets(id) ON DELETE CASCADE,
  customer_id                 INTEGER REFERENCES customers(id) ON DELETE SET NULL,
  address_line                TEXT    NOT NULL,
  city                        TEXT,
  state                       TEXT,
  postcode                    TEXT,
  lat                         REAL    NOT NULL,
  lng                         REAL    NOT NULL,
  scheduled_window_start      TEXT,
  scheduled_window_end        TEXT,
  priority                    TEXT    NOT NULL DEFAULT 'normal'
                                      CHECK (priority IN ('low','normal','high','emergency')),
  status                      TEXT    NOT NULL DEFAULT 'unassigned'
                                      CHECK (status IN ('unassigned','assigned','en_route','on_site','completed','canceled','deferred')),
  assigned_technician_id      INTEGER REFERENCES users(id),
  estimated_duration_minutes  INTEGER,
  actual_duration_minutes     INTEGER,
  technician_notes            TEXT,
  notes                       TEXT,
  created_by_user_id          INTEGER NOT NULL REFERENCES users(id),
  created_at                  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now')),
  updated_at                  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now'))
);

INSERT INTO field_service_jobs
  SELECT
    id,
    ticket_id,
    customer_id,
    address_line,
    city,
    state,
    postcode,
    lat,
    lng,
    scheduled_window_start,
    scheduled_window_end,
    priority,
    status,
    assigned_technician_id,
    estimated_duration_minutes,
    actual_duration_minutes,
    technician_notes,
    notes,
    created_by_user_id,
    created_at,
    updated_at
  FROM field_service_jobs_old;

DROP TABLE field_service_jobs_old;

CREATE INDEX IF NOT EXISTS idx_fsj_status_window
  ON field_service_jobs (status, scheduled_window_start);

CREATE INDEX IF NOT EXISTS idx_fsj_tech_status
  ON field_service_jobs (assigned_technician_id, status);

CREATE INDEX IF NOT EXISTS idx_fsj_latlng
  ON field_service_jobs (lat, lng);

-- ===========================================================================
-- SCAN-517: sync_conflicts — resolved_by_user_id gets ON DELETE SET NULL
-- Original DDL from migration 134.
-- Existing indices:
--   idx_sync_conflicts_status_reported (status, reported_at DESC)
--   idx_sync_conflicts_entity          (entity_kind, entity_id)
--   idx_sync_conflicts_reporter        (reporter_user_id)
-- ===========================================================================

ALTER TABLE sync_conflicts RENAME TO sync_conflicts_old;

CREATE TABLE sync_conflicts (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,

  -- What conflicted
  entity_kind           TEXT    NOT NULL,
  entity_id             INTEGER NOT NULL,

  -- Conflict classification
  conflict_type         TEXT    NOT NULL
                                CHECK (conflict_type IN (
                                  'concurrent_update',
                                  'stale_write',
                                  'duplicate_create',
                                  'deleted_remote'
                                )),

  -- Opaque blobs — callers decide shape; server treats as plain text
  client_version_json   TEXT    NOT NULL,
  server_version_json   TEXT    NOT NULL,

  -- Reporter metadata (client-supplied device_id is NOT verified)
  reporter_user_id      INTEGER NOT NULL REFERENCES users(id),
  reporter_device_id    TEXT,
  reporter_platform     TEXT
                                CHECK (reporter_platform IS NULL OR reporter_platform IN (
                                  'android', 'ios', 'web'
                                )),
  reported_at           TEXT    NOT NULL DEFAULT (datetime('now')),

  -- Queue lifecycle
  status                TEXT    NOT NULL DEFAULT 'pending'
                                CHECK (status IN ('pending','resolved','rejected','deferred')),

  -- Resolution (declarative)
  resolution            TEXT
                                CHECK (resolution IS NULL OR resolution IN (
                                  'keep_client', 'keep_server', 'merge', 'manual', 'rejected'
                                )),
  resolution_notes      TEXT,
  resolved_by_user_id   INTEGER REFERENCES users(id) ON DELETE SET NULL,
  resolved_at           TEXT
);

INSERT INTO sync_conflicts
  SELECT
    id,
    entity_kind,
    entity_id,
    conflict_type,
    client_version_json,
    server_version_json,
    reporter_user_id,
    reporter_device_id,
    reporter_platform,
    reported_at,
    status,
    resolution,
    resolution_notes,
    resolved_by_user_id,
    resolved_at
  FROM sync_conflicts_old;

DROP TABLE sync_conflicts_old;

CREATE INDEX IF NOT EXISTS idx_sync_conflicts_status_reported
  ON sync_conflicts (status, reported_at DESC);

CREATE INDEX IF NOT EXISTS idx_sync_conflicts_entity
  ON sync_conflicts (entity_kind, entity_id);

CREATE INDEX IF NOT EXISTS idx_sync_conflicts_reporter
  ON sync_conflicts (reporter_user_id);

-- ===========================================================================
-- SCAN-518: pl_snapshots — generated_by_user_id gets ON DELETE SET NULL
-- Original DDL from migration 131.
-- Existing indices:
--   idx_pl_snapshots_period (period_from, period_to)
-- ===========================================================================

ALTER TABLE pl_snapshots RENAME TO pl_snapshots_old;

CREATE TABLE pl_snapshots (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  tenant_slug_hint      TEXT,
  period_from           TEXT NOT NULL,
  period_to             TEXT NOT NULL,
  revenue_cents         INTEGER,
  cogs_cents            INTEGER,
  gross_profit_cents    INTEGER,
  expense_cents         INTEGER,
  net_profit_cents      INTEGER,
  tax_liability_cents   INTEGER,
  outstanding_ar_cents  INTEGER,
  inventory_value_cents INTEGER,
  metadata_json         TEXT,
  generated_at          TEXT DEFAULT (datetime('now')),
  generated_by_user_id  INTEGER REFERENCES users(id) ON DELETE SET NULL
);

INSERT INTO pl_snapshots
  SELECT
    id,
    tenant_slug_hint,
    period_from,
    period_to,
    revenue_cents,
    cogs_cents,
    gross_profit_cents,
    expense_cents,
    net_profit_cents,
    tax_liability_cents,
    outstanding_ar_cents,
    inventory_value_cents,
    metadata_json,
    generated_at,
    generated_by_user_id
  FROM pl_snapshots_old;

DROP TABLE pl_snapshots_old;

CREATE INDEX IF NOT EXISTS idx_pl_snapshots_period
  ON pl_snapshots (period_from, period_to);

-- ===========================================================================
COMMIT;

PRAGMA foreign_keys = ON;
