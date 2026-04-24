-- Migration 127: SMS Auto-Responders + Customer Groups + Group Messaging
-- SCAN-495: iOS §12 parity — smsApi auto-responders + group messaging

-- ---------------------------------------------------------------------------
-- Table: sms_auto_responders
-- Keyword/regex rules that match inbound SMS and return a canned response.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sms_auto_responders (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  name                 TEXT    NOT NULL,
  trigger_keyword      TEXT,
  rule_json            TEXT    NOT NULL,
  response_body        TEXT    NOT NULL,
  is_active            INTEGER NOT NULL DEFAULT 1,
  match_count          INTEGER NOT NULL DEFAULT 0,
  last_matched_at      TEXT,
  created_by_user_id   INTEGER NOT NULL REFERENCES users(id),
  created_at           TEXT    NOT NULL DEFAULT (datetime('now')),
  updated_at           TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_sms_auto_responders_is_active
  ON sms_auto_responders(is_active);

-- ---------------------------------------------------------------------------
-- Table: sms_customer_groups
-- Named lists of customers for bulk/group SMS sends.
-- is_dynamic=1: membership is recalculated from filter_json at send time.
-- is_dynamic=0: static list; members managed via sms_customer_group_members.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sms_customer_groups (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  name                 TEXT    NOT NULL,
  description          TEXT,
  filter_json          TEXT,
  is_dynamic           INTEGER NOT NULL DEFAULT 0,
  member_count_cache   INTEGER NOT NULL DEFAULT 0,
  created_by_user_id   INTEGER REFERENCES users(id),
  created_at           TEXT    NOT NULL DEFAULT (datetime('now')),
  updated_at           TEXT    NOT NULL DEFAULT (datetime('now')),
  UNIQUE(name)
);

-- ---------------------------------------------------------------------------
-- Table: sms_customer_group_members
-- Junction table for static groups.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sms_customer_group_members (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id    INTEGER NOT NULL REFERENCES sms_customer_groups(id) ON DELETE CASCADE,
  customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  added_at    TEXT    NOT NULL DEFAULT (datetime('now')),
  UNIQUE(group_id, customer_id)
);

CREATE INDEX IF NOT EXISTS idx_sms_customer_group_members_customer_id
  ON sms_customer_group_members(customer_id);

-- ---------------------------------------------------------------------------
-- Table: sms_group_sends
-- Audit trail + status tracking for each bulk group send.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sms_group_sends (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id         INTEGER REFERENCES sms_customer_groups(id),
  body             TEXT    NOT NULL,
  sender_user_id   INTEGER NOT NULL REFERENCES users(id),
  recipient_count  INTEGER,
  sent_count       INTEGER,
  failed_count     INTEGER,
  started_at       TEXT    NOT NULL DEFAULT (datetime('now')),
  completed_at     TEXT,
  status           TEXT    NOT NULL DEFAULT 'queued'
    CHECK(status IN ('queued','in_progress','completed','partial','failed'))
);

CREATE INDEX IF NOT EXISTS idx_sms_group_sends_sender_started
  ON sms_group_sends(sender_user_id, started_at);
