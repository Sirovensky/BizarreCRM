-- Migration 124: Activity events + notification preferences + held POS carts
-- SCAN-488, SCAN-472, SCAN-497

-- ---------------------------------------------------------------------------
-- activity_events
-- Generic structured event log. Every entity mutation can insert a row here
-- via the activityLog utility. actor_user_id may be NULL for system events.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS activity_events (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  actor_user_id   INTEGER REFERENCES users(id) ON DELETE SET NULL,
  entity_kind     TEXT    NOT NULL,
  entity_id       INTEGER,
  action          TEXT    NOT NULL,
  metadata_json   TEXT,
  created_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_activity_events_created_at
  ON activity_events (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_activity_events_actor_created
  ON activity_events (actor_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_activity_events_entity
  ON activity_events (entity_kind, entity_id);

-- ---------------------------------------------------------------------------
-- notification_preferences
-- Per-user per-event-type per-channel toggle with optional quiet hours blob.
-- PRIMARY KEY(user_id, event_type, channel) enforces uniqueness.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notification_preferences (
  user_id           INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event_type        TEXT    NOT NULL,
  channel           TEXT    NOT NULL CHECK(channel IN ('push','in_app','email','sms')),
  enabled           INTEGER NOT NULL DEFAULT 1,
  quiet_hours_json  TEXT,
  updated_at        TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now')),
  PRIMARY KEY (user_id, event_type, channel)
);

-- ---------------------------------------------------------------------------
-- held_carts
-- POS "park & recall" — carts frozen mid-transaction. Soft-deleted via
-- discarded_at; recalled_at records when the cart was restored.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS held_carts (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id          INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  workstation_id   INTEGER REFERENCES workstations(id) ON DELETE SET NULL,
  label            TEXT,
  cart_json        TEXT    NOT NULL,
  customer_id      INTEGER REFERENCES customers(id) ON DELETE SET NULL,
  total_cents      INTEGER,
  created_at       TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now')),
  recalled_at      TEXT,
  discarded_at     TEXT
);

CREATE INDEX IF NOT EXISTS idx_held_carts_user_created
  ON held_carts (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_held_carts_workstation_created
  ON held_carts (workstation_id, created_at DESC);
