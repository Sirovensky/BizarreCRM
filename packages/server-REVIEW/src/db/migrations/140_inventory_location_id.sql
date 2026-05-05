-- Migration 140: add location_id to inventory_items (SCAN-462 Phase 3)
--
-- Column is nullable (no NOT NULL) so single-location tenants see zero
-- behaviour change and existing rows remain valid after the backfill.
-- The FK references locations(id) with ON DELETE SET NULL so deleting a
-- location never orphans an inventory item — it just becomes unscoped.
--
-- Backfill sets every existing item to the seeded "Main Store" (id=1,
-- inserted idempotently by migration 132) before the index is built.

ALTER TABLE inventory_items
  ADD COLUMN location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL;

-- Backfill: assign all legacy items to the default store so existing
-- reports and filters produce meaningful results from day one.
UPDATE inventory_items SET location_id = 1 WHERE location_id IS NULL;

-- Composite index serves the primary multi-location query pattern:
-- "all active items at location X" — common for the location
-- dashboard and stock lookup pages.
CREATE INDEX IF NOT EXISTS idx_inventory_items_location_active
  ON inventory_items(location_id, is_active);
