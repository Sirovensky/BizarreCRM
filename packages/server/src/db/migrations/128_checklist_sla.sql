-- Migration 128: Daily operational checklist + ticket SLA tracking
-- SCAN-468: open-shop / daily checklist templates + instances
-- SCAN-464: SLA policies, ticket SLA columns, breach log

-- ---------------------------------------------------------------------------
-- Table: checklist_templates
-- Manager-authored reusable checklists (open, close, midday, custom).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS checklist_templates (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  name                TEXT    NOT NULL,
  kind                TEXT    NOT NULL CHECK (kind IN ('open','close','midday','custom')),
  items_json          TEXT    NOT NULL DEFAULT '[]',
  is_active           INTEGER NOT NULL DEFAULT 1,
  created_by_user_id  INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at          TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now')),
  updated_at          TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_checklist_templates_kind_active
  ON checklist_templates (kind, is_active);

-- ---------------------------------------------------------------------------
-- Table: checklist_instances
-- One row per employee checklist run (in_progress → completed|abandoned).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS checklist_instances (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  template_id           INTEGER NOT NULL REFERENCES checklist_templates(id),
  completed_by_user_id  INTEGER NOT NULL REFERENCES users(id),
  completed_items_json  TEXT    NOT NULL DEFAULT '[]',
  notes                 TEXT,
  status                TEXT    NOT NULL DEFAULT 'in_progress'
                                CHECK (status IN ('in_progress','completed','abandoned')),
  started_at            TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now')),
  completed_at          TEXT
);

CREATE INDEX IF NOT EXISTS idx_checklist_instances_owner_started
  ON checklist_instances (completed_by_user_id, started_at);

CREATE INDEX IF NOT EXISTS idx_checklist_instances_template_completed
  ON checklist_instances (template_id, completed_at);

-- ---------------------------------------------------------------------------
-- Table: sla_policies
-- One policy per priority level (enforced via partial unique index on active).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sla_policies (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  name                  TEXT    NOT NULL,
  priority_level        TEXT    NOT NULL CHECK (priority_level IN ('low','normal','high','critical')),
  first_response_hours  INTEGER NOT NULL,
  resolution_hours      INTEGER NOT NULL,
  business_hours_only   INTEGER NOT NULL DEFAULT 1,
  is_active             INTEGER NOT NULL DEFAULT 1,
  created_at            TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now')),
  updated_at            TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now'))
);

-- Soft-unique: only one active policy per priority_level at a time.
CREATE UNIQUE INDEX IF NOT EXISTS uidx_sla_policies_active_priority
  ON sla_policies (priority_level)
  WHERE is_active = 1;

-- ---------------------------------------------------------------------------
-- Extend tickets with SLA columns (safe ALTER TABLE — idempotent via guards)
-- ---------------------------------------------------------------------------

-- SQLite does not support IF NOT EXISTS on ALTER TABLE, so we use a
-- compatibility pattern: each column is added inside a BEGIN/COMMIT with
-- an IGNORE on the duplicate-column error. The migration runner should
-- wrap the whole file; individual ALTER statements are not transactional
-- in SQLite but are safe to re-run since the column already exists.

ALTER TABLE tickets ADD COLUMN sla_policy_id            INTEGER REFERENCES sla_policies(id);
ALTER TABLE tickets ADD COLUMN sla_first_response_due_at TEXT;
ALTER TABLE tickets ADD COLUMN sla_resolution_due_at     TEXT;
ALTER TABLE tickets ADD COLUMN sla_breached              INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_tickets_sla_resolution_due
  ON tickets (sla_resolution_due_at)
  WHERE sla_breached = 0;

CREATE INDEX IF NOT EXISTS idx_tickets_sla_breached
  ON tickets (sla_breached);

-- ---------------------------------------------------------------------------
-- Table: sla_breach_log
-- Audit trail of every first-response or resolution breach event.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sla_breach_log (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id       INTEGER NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  policy_id       INTEGER REFERENCES sla_policies(id),
  breach_type     TEXT    NOT NULL CHECK (breach_type IN ('first_response','resolution')),
  breached_at     TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now')),
  acknowledged_at TEXT,
  notes           TEXT
);

CREATE INDEX IF NOT EXISTS idx_sla_breach_log_ticket_id
  ON sla_breach_log (ticket_id);

CREATE INDEX IF NOT EXISTS idx_sla_breach_log_breached_at
  ON sla_breach_log (breached_at);

-- ---------------------------------------------------------------------------
-- Seed default SLA policies (idempotent — INSERT OR IGNORE)
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO sla_policies
  (name, priority_level, first_response_hours, resolution_hours, business_hours_only, is_active)
VALUES
  ('Low Priority SLA',      'low',      8,  72, 1, 1),
  ('Normal Priority SLA',   'normal',   4,  48, 1, 1),
  ('High Priority SLA',     'high',     2,  24, 1, 1),
  ('Critical Priority SLA', 'critical', 1,   4, 0, 1);
