-- SCAN-1148: migrations 139-142 backfilled `location_id = 1` assuming the
-- seeded "Main Store" row from migration 132 would always live at id=1.
-- On tenants that deleted + re-created locations before 139 ran, id=1 may
-- not exist — the backfill then wrote an FK value pointing at nothing.
-- The ON DELETE SET NULL clauses on the FK don't help here because the
-- row never existed in the first place.
--
-- Repair pass: for every table whose location_id column was backfilled to
-- 1 by the earlier migrations, re-point any row whose location_id is now
-- orphan (NOT EXISTS a matching locations row) to the current default
-- location (is_default=1). If no default exists, leave as NULL — the
-- FK's SET NULL semantics + UI fallbacks handle that gracefully.
--
-- Idempotent: each UPDATE only matches orphan rows; a subsequent run after
-- the first fix finds nothing to update. Safe to re-run if a tenant's
-- locations table is rebuilt again.

-- Pre-compute the resolved default id ONCE. The expression
-- `(SELECT id FROM locations WHERE is_default=1 ORDER BY id LIMIT 1)`
-- returns NULL if no default is configured — same outcome as SET NULL.

-- invoices
UPDATE invoices
   SET location_id = (SELECT id FROM locations WHERE is_default = 1 ORDER BY id LIMIT 1)
 WHERE location_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM locations WHERE locations.id = invoices.location_id);

-- inventory_items
UPDATE inventory_items
   SET location_id = (SELECT id FROM locations WHERE is_default = 1 ORDER BY id LIMIT 1)
 WHERE location_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM locations WHERE locations.id = inventory_items.location_id);

-- users (home_location_id)
UPDATE users
   SET home_location_id = (SELECT id FROM locations WHERE is_default = 1 ORDER BY id LIMIT 1)
 WHERE home_location_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM locations WHERE locations.id = users.home_location_id);

-- tickets (location_id from migration 136)
UPDATE tickets
   SET location_id = (SELECT id FROM locations WHERE is_default = 1 ORDER BY id LIMIT 1)
 WHERE location_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM locations WHERE locations.id = tickets.location_id);

-- Work-location-scoped tables from migration 142 — expenses, clock_entries,
-- shift_schedules, appointments. Every tenant that successfully applied
-- 142 has all four (142 has no @skip-if-no-table directive, so any
-- missing table would have hard-failed its run).

UPDATE expenses
   SET location_id = (SELECT id FROM locations WHERE is_default = 1 ORDER BY id LIMIT 1)
 WHERE location_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM locations WHERE locations.id = expenses.location_id);

UPDATE clock_entries
   SET location_id = (SELECT id FROM locations WHERE is_default = 1 ORDER BY id LIMIT 1)
 WHERE location_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM locations WHERE locations.id = clock_entries.location_id);

UPDATE shift_schedules
   SET location_id = (SELECT id FROM locations WHERE is_default = 1 ORDER BY id LIMIT 1)
 WHERE location_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM locations WHERE locations.id = shift_schedules.location_id);

UPDATE appointments
   SET location_id = (SELECT id FROM locations WHERE is_default = 1 ORDER BY id LIMIT 1)
 WHERE location_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM locations WHERE locations.id = appointments.location_id);
