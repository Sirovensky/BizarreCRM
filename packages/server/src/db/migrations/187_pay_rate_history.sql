-- Migration 187 — WEB-UIUX-1264: persist every pay_rate change with the
-- effective_at timestamp + actor so payroll can answer "which rate applied
-- on payday?" without trusting the live users.pay_rate value.
--
-- Trigger seeds an initial row from the existing users.pay_rate snapshot on
-- first edit going forward (no backfill — legacy rates pre-this-migration
-- show only as "starting rate, effective unknown" in the UI).
CREATE TABLE IF NOT EXISTS pay_rate_history (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id         INTEGER NOT NULL REFERENCES users(id),
  pay_rate        REAL,
  effective_at    TEXT NOT NULL DEFAULT (datetime('now')),
  changed_by_user_id INTEGER REFERENCES users(id),
  note            TEXT
);

CREATE INDEX IF NOT EXISTS idx_pay_rate_history_user
  ON pay_rate_history(user_id, effective_at);
