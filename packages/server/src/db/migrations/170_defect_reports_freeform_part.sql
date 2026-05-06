-- Migration 170: WEB-UIUX-655 — allow defect reports for freeform / custom
-- parts that have no inventory_item_id. The column becomes nullable and a new
-- part_name column stores the freeform label when inventory_item_id is NULL.
--
-- SQLite does not support DROP NOT NULL via ALTER COLUMN, so we recreate the
-- table using the standard shadow-copy strategy.

-- 1. Shadow table with the new schema.
CREATE TABLE IF NOT EXISTS parts_defect_reports_new (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  inventory_item_id    INTEGER,                  -- NULL for freeform / custom parts
  part_name            TEXT,                     -- freeform name when inventory_item_id IS NULL
  ticket_id            INTEGER,                  -- NULL = caught before install
  reported_by_user_id  INTEGER NOT NULL,
  defect_type          TEXT,                     -- doa | intermittent | cosmetic | wrong_spec
  description          TEXT,
  photo_path           TEXT,
  reported_at          TEXT NOT NULL DEFAULT (datetime('now')),
  CHECK (inventory_item_id IS NOT NULL OR (part_name IS NOT NULL AND part_name != ''))
);

-- 2. Copy existing rows (all have inventory_item_id set; part_name stays NULL).
INSERT INTO parts_defect_reports_new
  (id, inventory_item_id, part_name, ticket_id, reported_by_user_id,
   defect_type, description, photo_path, reported_at)
SELECT
  id, inventory_item_id, NULL, ticket_id, reported_by_user_id,
  defect_type, description, photo_path, reported_at
FROM parts_defect_reports;

-- 3. Swap.
DROP TABLE parts_defect_reports;
ALTER TABLE parts_defect_reports_new RENAME TO parts_defect_reports;

-- 4. Restore indexes.
CREATE INDEX IF NOT EXISTS idx_defect_reports_item
  ON parts_defect_reports(inventory_item_id, reported_at);
CREATE INDEX IF NOT EXISTS idx_defect_reports_ticket
  ON parts_defect_reports(ticket_id);
CREATE INDEX IF NOT EXISTS idx_defect_reports_user
  ON parts_defect_reports(reported_by_user_id);
