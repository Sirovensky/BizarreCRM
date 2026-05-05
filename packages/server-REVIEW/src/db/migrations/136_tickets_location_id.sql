-- Migration 136: add location_id to tickets (SCAN-462 follow-up, phase 1 of N)
--
-- Column is nullable (no NOT NULL) so single-location tenants see zero
-- behaviour change and existing rows remain valid after the backfill.
-- The FK references locations(id) with ON DELETE SET NULL so deleting a
-- location never orphans a ticket — it just becomes unscoped.
--
-- Backfill sets every existing ticket to the seeded "Main Store" (id=1,
-- inserted idempotently by migration 132) before the index is built.

ALTER TABLE tickets
  ADD COLUMN location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL;

-- Backfill: assign all legacy tickets to the default store so existing
-- reports and filters produce meaningful results from day one.
UPDATE tickets SET location_id = 1 WHERE location_id IS NULL;

-- Composite index serves the primary multi-location query pattern:
-- "all tickets at location X with status Y" — common for the location
-- dashboard and dispatch queue pages.
CREATE INDEX IF NOT EXISTS idx_tickets_location_status
  ON tickets(location_id, status_id);
