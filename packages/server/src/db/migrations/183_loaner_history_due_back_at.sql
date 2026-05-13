-- Migration 183 — WEB-UIUX-641: capture expected return time on every loan.
-- Loan path used to store it inside the free-text `notes` column, which made
-- "who hasn't returned by X" reporting impossible. New `due_back_at` is a
-- nullable ISO timestamp written at /loan time; the server's overdue helper
-- and the loaner list both read it. No backfill — historical loans without a
-- due date stay NULL and are excluded from the overdue list.
ALTER TABLE loaner_history ADD COLUMN due_back_at TEXT;
CREATE INDEX IF NOT EXISTS idx_loaner_history_due_back_at
  ON loaner_history(due_back_at) WHERE returned_at IS NULL AND due_back_at IS NOT NULL;
