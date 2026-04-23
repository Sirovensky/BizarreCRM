-- Migration 125: Ticket labels + shared-device mode settings
-- SCAN-470: ticket_labels + ticket_label_assignments tables
-- SCAN-469: shared_device_* store_config keys seeded

-- ---------------------------------------------------------------------------
-- Table: ticket_labels
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ticket_labels (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT    NOT NULL,
  color_hex   TEXT    NOT NULL DEFAULT '#888888',
  description TEXT,
  is_active   INTEGER NOT NULL DEFAULT 1,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  created_at  TEXT    DEFAULT (datetime('now')),
  updated_at  TEXT    DEFAULT (datetime('now')),
  UNIQUE(name)
);

-- ---------------------------------------------------------------------------
-- Table: ticket_label_assignments
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ticket_label_assignments (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id  INTEGER NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  label_id   INTEGER NOT NULL REFERENCES ticket_labels(id) ON DELETE CASCADE,
  created_at TEXT    DEFAULT (datetime('now')),
  UNIQUE(ticket_id, label_id)
);

CREATE INDEX IF NOT EXISTS idx_ticket_label_assignments_ticket_id
  ON ticket_label_assignments(ticket_id);

CREATE INDEX IF NOT EXISTS idx_ticket_label_assignments_label_id
  ON ticket_label_assignments(label_id);

-- ---------------------------------------------------------------------------
-- Seed shared-device mode defaults into store_config (idempotent)
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO store_config (key, value) VALUES ('shared_device_mode_enabled', '0');
INSERT OR IGNORE INTO store_config (key, value) VALUES ('shared_device_auto_logoff_minutes', '0');
INSERT OR IGNORE INTO store_config (key, value) VALUES ('shared_device_require_pin_on_switch', '1');
