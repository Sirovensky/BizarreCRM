-- Migration 141: add home_location_id to users (SCAN-462 Phase 4)
--
-- users.home_location_id is a UI-defaulting convenience column that tells
-- the frontend which location to pre-select when a user logs in. It is NOT
-- an access-control column — the user_locations junction table (migration 132)
-- governs which locations a user may actually access.
--
-- Priority resolution at login (implemented in locations.routes.ts):
--   1. users.home_location_id   (if set and location is active)
--   2. user_locations.is_primary=1  (junction table primary assignment)
--   3. locations.is_default=1   (global store default)
--
-- Column is nullable: no NOT NULL constraint. The backfill below sets a
-- sensible default (primary assignment if any, else location 1) only for
-- existing rows. New users that have no assignment yet will get NULL until
-- their home location is explicitly set.
--
-- FK uses ON DELETE SET NULL so removing a location never corrupts user rows.

ALTER TABLE users
  ADD COLUMN home_location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL;

-- Backfill step 1: populate from user_locations.is_primary=1 assignment
-- (the canonical "home location" per the junction table).
UPDATE users SET home_location_id = (
  SELECT location_id FROM user_locations
  WHERE user_locations.user_id = users.id AND user_locations.is_primary = 1
  LIMIT 1
) WHERE home_location_id IS NULL;

-- Backfill step 2: any user still without a home location falls back to
-- the seeded "Main Store" (id=1, guaranteed by migration 132).
UPDATE users SET home_location_id = 1 WHERE home_location_id IS NULL;

-- Index: supports the reverse lookup "all users whose home is location X"
-- (useful for location-dashboard user count and shift scheduling queries).
CREATE INDEX IF NOT EXISTS idx_users_home_location
  ON users(home_location_id);
