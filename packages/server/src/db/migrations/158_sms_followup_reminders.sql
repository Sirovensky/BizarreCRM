-- WEB-UNWIRED-014: persistent SMS follow-up reminders.
-- Replaces the old browser-local `sms_reminders` array with tenant DB rows
-- that the server can notify on, snooze, complete, and audit.

CREATE TABLE IF NOT EXISTS sms_followup_reminders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  conv_phone TEXT NOT NULL,
  phone TEXT NOT NULL,
  customer_id INTEGER REFERENCES customers(id) ON DELETE SET NULL,
  label TEXT NOT NULL,
  note TEXT,
  due_at TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK(status IN ('pending', 'completed', 'cancelled')),
  notified_at TEXT,
  created_by INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  completed_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  completed_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_sms_followup_reminders_due
  ON sms_followup_reminders(status, due_at, notified_at);

CREATE INDEX IF NOT EXISTS idx_sms_followup_reminders_conv_phone
  ON sms_followup_reminders(conv_phone, status, due_at);

CREATE INDEX IF NOT EXISTS idx_sms_followup_reminders_created_by
  ON sms_followup_reminders(created_by, status, due_at);
