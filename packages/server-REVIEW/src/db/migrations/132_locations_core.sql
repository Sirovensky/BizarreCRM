-- Migration 132: Multi-location core
-- SCAN-462: Multi-location management (android §63 / ios §60)
-- Tables: locations, user_locations
--
-- SCOPE NOTICE: This migration adds ONLY the core location registry and
-- user-location assignments. It intentionally does NOT add location_id to
-- tickets, invoices, inventory, or any other domain table. That wire-up
-- is a separate multi-day epic that requires planning before implementation.
-- Until that follow-up migration lands, all domain queries remain un-scoped
-- by location. Single-location tenants (the current majority) see zero
-- behaviour change.

-- ---------------------------------------------------------------------------
-- Table: locations
-- One row per physical store / service location.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS locations (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  name          TEXT    NOT NULL,
  address_line  TEXT,
  city          TEXT,
  state         TEXT,
  postcode      TEXT,
  country       TEXT    NOT NULL DEFAULT 'US',
  phone         TEXT,
  email         TEXT,
  lat           REAL,
  lng           REAL,
  timezone      TEXT    NOT NULL DEFAULT 'America/New_York',
  is_active     INTEGER NOT NULL DEFAULT 1,
  is_default    INTEGER NOT NULL DEFAULT 0,
  notes         TEXT,
  created_at    TEXT    NOT NULL DEFAULT (datetime('now')),
  updated_at    TEXT    NOT NULL DEFAULT (datetime('now')),
  UNIQUE(name)
);

-- ---------------------------------------------------------------------------
-- Trigger: trg_locations_single_default
-- Enforces the invariant that at most one location may have is_default=1.
-- Fires on INSERT and UPDATE; when the incoming row sets is_default=1 it
-- clears all other rows first, then the new row lands with is_default=1.
-- Idempotent: running twice for the same id leaves the table consistent.
-- ---------------------------------------------------------------------------
CREATE TRIGGER IF NOT EXISTS trg_locations_single_default_insert
  BEFORE INSERT ON locations
  WHEN NEW.is_default = 1
BEGIN
  UPDATE locations SET is_default = 0 WHERE is_default = 1;
END;

CREATE TRIGGER IF NOT EXISTS trg_locations_single_default_update
  BEFORE UPDATE OF is_default ON locations
  WHEN NEW.is_default = 1
BEGIN
  UPDATE locations SET is_default = 0 WHERE is_default = 1 AND id != NEW.id;
END;

-- ---------------------------------------------------------------------------
-- Table: user_locations
-- Maps users to one or more locations. is_primary=1 marks the user's home
-- location for scheduling / filtering. role_at_location overrides the global
-- users.role within a location context (reserved for future enforcement).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_locations (
  user_id          INTEGER NOT NULL REFERENCES users(id)     ON DELETE CASCADE,
  location_id      INTEGER NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
  is_primary       INTEGER NOT NULL DEFAULT 0,
  role_at_location TEXT,
  assigned_at      TEXT    NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, location_id)
);

CREATE INDEX IF NOT EXISTS idx_user_locations_location_id
  ON user_locations(location_id);

-- ---------------------------------------------------------------------------
-- Seed: ensure a default "Main Store" location exists so single-location
-- tenants are automatically on-boarded with id=1 as their home location.
-- INSERT OR IGNORE guarantees idempotency across repeated migration runs.
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO locations (id, name, is_default, is_active)
  VALUES (1, 'Main Store', 1, 1);
