-- §1.3 updated_at + _synced_at bookkeeping
-- Every table records updated_at (server time) and _synced_at (device clock
-- at point of last successful sync round-trip) so delta-sync can ask
-- ?since=<last_synced_at> and detect rows that changed server-side since last pull.
--
-- This migration adds _synced_at to the tables that exist in migrations 001-002.
-- Domain-specific tables (invoice, appointment, expense, etc.) add _synced_at
-- in their own domain migration when those tables are first created.
--
-- All ALTER TABLE statements use "ADD COLUMN … DEFAULT NULL" (SQLite no-rebuild).
-- Existing rows receive NULL; they refresh on the next delta-sync pass.

-- Core tables from 001_initial.sql
ALTER TABLE customer    ADD COLUMN _synced_at TEXT;
ALTER TABLE ticket      ADD COLUMN _synced_at TEXT;
ALTER TABLE inventory   ADD COLUMN _synced_at TEXT;

-- Partial indexes: surface rows whose server updated_at timestamp is newer
-- than the last device sync.  NULL _synced_at = never synced = always stale.
CREATE INDEX IF NOT EXISTS idx_customer_sync_due  ON customer(updated_at)  WHERE _synced_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_ticket_sync_due    ON ticket(updated_at)    WHERE _synced_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_inventory_sync_due ON inventory(updated_at) WHERE _synced_at IS NULL;
