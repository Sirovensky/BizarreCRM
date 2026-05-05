-- Migration 133: Appointment Self-Booking Admin Configuration
-- SCAN-471: Booking portal admin config (android §58.3)
-- Tables: booking_services, booking_hours, booking_exceptions
-- Settings keys: booking_enabled, booking_min_notice_hours,
--   booking_max_lead_days, booking_require_phone, booking_require_email,
--   booking_confirmation_mode

-- ---------------------------------------------------------------------------
-- Table: booking_services
-- One row per service type offered on the self-booking portal.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS booking_services (
  id                      INTEGER PRIMARY KEY AUTOINCREMENT,
  name                    TEXT    NOT NULL,
  description             TEXT,
  duration_minutes        INTEGER NOT NULL CHECK (duration_minutes > 0),
  buffer_before_minutes   INTEGER NOT NULL DEFAULT 0,
  buffer_after_minutes    INTEGER NOT NULL DEFAULT 0,
  deposit_required        INTEGER NOT NULL DEFAULT 0,
  deposit_amount_cents    INTEGER          DEFAULT 0
                                  CHECK (deposit_amount_cents >= 0),
  is_active               INTEGER NOT NULL DEFAULT 1,
  sort_order              INTEGER          DEFAULT 0,
  visible_on_booking      INTEGER NOT NULL DEFAULT 1,
  created_at              TEXT    NOT NULL DEFAULT (datetime('now')),
  updated_at              TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uidx_booking_services_name
  ON booking_services (name);

CREATE INDEX IF NOT EXISTS idx_booking_services_active_visible
  ON booking_services (is_active, visible_on_booking, sort_order);

-- ---------------------------------------------------------------------------
-- Table: booking_hours
-- One row per day-of-week (0=Sun … 6=Sat).
-- UNIQUE(day_of_week) — one schedule per weekday.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS booking_hours (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  day_of_week   INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  open_time     TEXT    NOT NULL,
  close_time    TEXT    NOT NULL,
  is_active     INTEGER NOT NULL DEFAULT 1
);

CREATE UNIQUE INDEX IF NOT EXISTS uidx_booking_hours_day
  ON booking_hours (day_of_week);

-- ---------------------------------------------------------------------------
-- Table: booking_exceptions
-- Holiday overrides, special-hours days, or forced closures.
-- UNIQUE(date) — one exception record per calendar date.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS booking_exceptions (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  date        TEXT    NOT NULL,
  is_closed   INTEGER NOT NULL DEFAULT 1,
  open_time   TEXT,
  close_time  TEXT,
  reason      TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS uidx_booking_exceptions_date
  ON booking_exceptions (date);

CREATE INDEX IF NOT EXISTS idx_booking_exceptions_date
  ON booking_exceptions (date);

-- ---------------------------------------------------------------------------
-- Seed default booking_hours (Mon–Sat 09:00–17:00, Sun closed)
-- day_of_week: 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO booking_hours (day_of_week, open_time, close_time, is_active)
VALUES
  (0, '09:00', '17:00', 0),  -- Sunday   — closed by default
  (1, '09:00', '17:00', 1),  -- Monday
  (2, '09:00', '17:00', 1),  -- Tuesday
  (3, '09:00', '17:00', 1),  -- Wednesday
  (4, '09:00', '17:00', 1),  -- Thursday
  (5, '09:00', '17:00', 1),  -- Friday
  (6, '09:00', '17:00', 1);  -- Saturday

-- ---------------------------------------------------------------------------
-- store_config settings keys
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO store_config (key, value) VALUES ('booking_enabled',              '0');
INSERT OR IGNORE INTO store_config (key, value) VALUES ('booking_min_notice_hours',     '24');
INSERT OR IGNORE INTO store_config (key, value) VALUES ('booking_max_lead_days',        '30');
INSERT OR IGNORE INTO store_config (key, value) VALUES ('booking_require_phone',        '1');
INSERT OR IGNORE INTO store_config (key, value) VALUES ('booking_require_email',        '0');
INSERT OR IGNORE INTO store_config (key, value) VALUES ('booking_confirmation_mode',    'manual');
