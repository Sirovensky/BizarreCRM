-- ============================================================================
-- Migration 121 — Shift Schedule + Time-Off + Timesheet (SCAN-475/484/485)
-- ============================================================================
--
-- Migration 096 created shift_schedules and time_off_requests but with
-- minimal columns. This migration extends those tables and adds the two new
-- tables needed for shift swaps and timesheet-edit auditing.
--
-- ALTER TABLE statements run once (migration runner guards idempotency).
-- CREATE TABLE / INDEX statements use IF NOT EXISTS for safety.
-- ============================================================================

-- ── 1. Extend shift_schedules ───────────────────────────────────────────────
-- Add location_id, role_tag, and updated_at (migration 096 only had `role`).
-- SQLite does not support IF NOT EXISTS on ALTER TABLE; migrations run once per
-- DB so this is safe. FK constraints cannot be added retroactively in SQLite.

ALTER TABLE shift_schedules ADD COLUMN location_id INTEGER;
-- role_tag alongside legacy `role` for API contract parity
ALTER TABLE shift_schedules ADD COLUMN role_tag TEXT;
-- updated_at for optimistic-concurrency friendly PATCH responses
ALTER TABLE shift_schedules ADD COLUMN updated_at TEXT;

-- Ensure composite index on (user_id, start_at) exists (096 already creates it,
-- IF NOT EXISTS makes this idempotent).
CREATE INDEX IF NOT EXISTS idx_shift_schedules_user_start_at
  ON shift_schedules(user_id, start_at);

-- ── 2. Extend time_off_requests ─────────────────────────────────────────────
-- Migration 096 columns: user_id, start_date, end_date, reason, status,
--   requested_at, approved_by_user_id, approved_at.
-- We need: kind, approver_user_id, decided_at, denial_reason.
-- `approved_by_user_id` / `approved_at` are the 096 equivalents; we add the
-- spec-aligned aliases and the missing columns.

ALTER TABLE time_off_requests ADD COLUMN kind TEXT
  CHECK (kind IN ('pto','sick','unpaid'));
ALTER TABLE time_off_requests ADD COLUMN approver_user_id INTEGER;
ALTER TABLE time_off_requests ADD COLUMN decided_at TEXT;
ALTER TABLE time_off_requests ADD COLUMN denial_reason TEXT;

-- Ensure (user_id, status) index exists.
CREATE INDEX IF NOT EXISTS idx_time_off_requests_user_status
  ON time_off_requests(user_id, status);

-- ── 3. Shift swap requests ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS shift_swap_requests (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  requester_user_id   INTEGER NOT NULL REFERENCES users(id),
  target_user_id      INTEGER NOT NULL REFERENCES users(id),
  shift_id            INTEGER NOT NULL REFERENCES shift_schedules(id) ON DELETE CASCADE,
  status              TEXT    NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','accepted','declined','canceled')),
  created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
  decided_at          TEXT
);

CREATE INDEX IF NOT EXISTS idx_shift_swap_target_status
  ON shift_swap_requests(target_user_id, status);

CREATE INDEX IF NOT EXISTS idx_shift_swap_requester
  ON shift_swap_requests(requester_user_id, status);

-- ── 4. Clock-entry edit audit log ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS clock_entry_edits (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  clock_entry_id  INTEGER NOT NULL REFERENCES clock_entries(id),
  editor_user_id  INTEGER NOT NULL REFERENCES users(id),
  before_json     TEXT    NOT NULL,
  after_json      TEXT    NOT NULL,
  reason          TEXT    NOT NULL,
  created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_clock_entry_edits_entry
  ON clock_entry_edits(clock_entry_id, created_at);
