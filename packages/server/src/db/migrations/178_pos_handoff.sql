-- POS-PHONE-TAP-1: pair a user's mobile device so the desktop POS / ticket
-- list / SMS app can push a "call this number" or "send this SMS draft"
-- command to the phone in their pocket. Two tables:
--   user_paired_devices   — long-lived pairing (token, label, last_seen_at)
--   pos_handoff_queue     — short-lived queue of pending actions; the paired
--                            device drains via GET /pos/handoff/poll
-- The web POS / ticket UI calls POST /pos/handoff to enqueue.

CREATE TABLE IF NOT EXISTS user_paired_devices (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id          INTEGER NOT NULL,
  device_token     TEXT NOT NULL UNIQUE,
  device_label     TEXT,
  platform         TEXT,
  push_endpoint    TEXT,
  push_p256dh      TEXT,
  push_auth        TEXT,
  last_seen_at     TEXT,
  created_at       TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_user_paired_devices_user ON user_paired_devices(user_id);
CREATE INDEX IF NOT EXISTS idx_user_paired_devices_last_seen ON user_paired_devices(last_seen_at);

CREATE TABLE IF NOT EXISTS pos_handoff_queue (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  target_user_id   INTEGER NOT NULL,
  target_device_id INTEGER,
  action           TEXT NOT NULL CHECK (action IN ('call', 'sms_draft')),
  phone            TEXT NOT NULL,
  payload_json     TEXT,
  status           TEXT NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'delivered', 'expired', 'cancelled')),
  created_by       INTEGER NOT NULL,
  created_at       TEXT NOT NULL DEFAULT (datetime('now')),
  delivered_at     TEXT,
  expires_at       TEXT NOT NULL,
  FOREIGN KEY (target_user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (target_device_id) REFERENCES user_paired_devices(id) ON DELETE CASCADE,
  FOREIGN KEY (created_by) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_pos_handoff_pending
  ON pos_handoff_queue(target_user_id, status, expires_at);
