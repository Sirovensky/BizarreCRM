-- Migration 120: expense approvals + mileage + per-diem
-- Adds approval workflow columns and subtype/detail columns to expenses table.
-- SQLite does not support adding NOT NULL columns without a DEFAULT, so all new
-- columns either have a DEFAULT or are nullable.

ALTER TABLE expenses ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'
  CHECK(status IN ('pending','approved','denied'));

ALTER TABLE expenses ADD COLUMN approved_by_user_id INTEGER REFERENCES users(id);

ALTER TABLE expenses ADD COLUMN approved_at TEXT;

ALTER TABLE expenses ADD COLUMN denial_reason TEXT;

ALTER TABLE expenses ADD COLUMN expense_subtype TEXT NOT NULL DEFAULT 'general'
  CHECK(expense_subtype IN ('general','mileage','perdiem'));

ALTER TABLE expenses ADD COLUMN mileage_miles REAL;

ALTER TABLE expenses ADD COLUMN mileage_rate_cents INTEGER;

ALTER TABLE expenses ADD COLUMN perdiem_days INTEGER;

ALTER TABLE expenses ADD COLUMN perdiem_rate_cents INTEGER;

CREATE INDEX IF NOT EXISTS idx_expenses_status_created ON expenses(status, created_at);
