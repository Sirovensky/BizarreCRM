-- Migration 139: add location_id to invoices (SCAN-462 Phase 2)
--
-- Column is nullable (no NOT NULL) so single-location tenants see zero
-- behaviour change and existing rows remain valid after the backfill.
-- The FK references locations(id) with ON DELETE SET NULL so deleting a
-- location never orphans an invoice — it just becomes unscoped.
--
-- Backfill sets every existing invoice to the seeded "Main Store" (id=1,
-- inserted idempotently by migration 132) before the index is built.

ALTER TABLE invoices
  ADD COLUMN location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL;

-- Backfill: assign all legacy invoices to the default store so existing
-- reports and filters produce meaningful results from day one.
UPDATE invoices SET location_id = 1 WHERE location_id IS NULL;

-- Composite index serves the primary multi-location query pattern:
-- "all invoices at location X with status Y" — common for the location
-- dashboard and receivables pages.
CREATE INDEX IF NOT EXISTS idx_invoices_location_status
  ON invoices(location_id, status);
