-- Migration 142: add location_id to work-location-scoped tables (Phase 5)
--
-- Adds location_id to four tables that are inherently scoped to where work
-- happens. Each column uses ON DELETE SET NULL so removing a location never
-- orphans existing rows.
--
-- Tables:
--   expenses       — the location at which the employee submitted the expense
--   clock_entries  — the location the employee clocked in/out at
--   shift_schedules — the location a scheduled shift belongs to
--   appointments   — the location at which the appointment is booked
--
-- Backfill: all existing rows default to location 1 (Main Store, seeded by
-- migration 132). New rows should supply an explicit location_id; the expenses
-- route defaults to 1 when the caller omits it.

-- ─── expenses ────────────────────────────────────────────────────────────────

ALTER TABLE expenses
  ADD COLUMN location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL;

UPDATE expenses SET location_id = 1 WHERE location_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_expenses_location
  ON expenses(location_id);

-- ─── clock_entries ───────────────────────────────────────────────────────────

ALTER TABLE clock_entries
  ADD COLUMN location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL;

UPDATE clock_entries SET location_id = 1 WHERE location_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_clock_entries_location
  ON clock_entries(location_id);

-- ─── shift_schedules ─────────────────────────────────────────────────────────

ALTER TABLE shift_schedules
  ADD COLUMN location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL;

UPDATE shift_schedules SET location_id = 1 WHERE location_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_shift_schedules_location
  ON shift_schedules(location_id);

-- ─── appointments ────────────────────────────────────────────────────────────

ALTER TABLE appointments
  ADD COLUMN location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL;

UPDATE appointments SET location_id = 1 WHERE location_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_appointments_location
  ON appointments(location_id);
