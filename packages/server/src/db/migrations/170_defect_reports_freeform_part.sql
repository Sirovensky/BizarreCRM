-- Migration 170: WEB-UIUX-655 — allow defect reports for freeform / custom
-- parts that have no inventory_item_id. The column becomes nullable and a new
-- part_name column stores the freeform label when inventory_item_id is NULL.
--
-- SQLite does not support DROP NOT NULL via ALTER COLUMN, so we recreate the
-- table using the standard shadow-copy strategy.
--
-- IMPORTANT: TWO triggers in migration 097 reference parts_defect_reports:
--   - trg_ticket_del_enrichment_cleanup    (line 127 — UPDATE ... ticket_id)
--   - trg_inventory_del_enrichment_cleanup (line 182 — DELETE FROM)
-- With PRAGMA legacy_alter_table=OFF (the modern default since SQLite 3.25),
-- the integrity check fires when the table is dropped and any trigger now
-- points at a missing table — the migration aborts with "no such table:
-- main.parts_defect_reports". We drop BOTH triggers before the swap and
-- recreate them verbatim afterward.

-- 0. Drop the two triggers that reference parts_defect_reports. Recreated
--    at the end of this migration so the cleanup behaviour is preserved.
DROP TRIGGER IF EXISTS trg_ticket_del_enrichment_cleanup;
DROP TRIGGER IF EXISTS trg_inventory_del_enrichment_cleanup;

-- 0a. Idempotency: if a prior failed run of this migration left a partial
--     parts_defect_reports_new shadow table around, drop it so the CREATE
--     below starts from a clean slate.
DROP TABLE IF EXISTS parts_defect_reports_new;

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

-- 5. Recreate trg_ticket_del_enrichment_cleanup verbatim from migration 097
--    so ticket deletes still cascade-cleanup enrichment tables. If this body
--    diverges from migration 097, the source of truth becomes whichever
--    migration last touched it; keep them in sync if 097 ever changes.
CREATE TRIGGER IF NOT EXISTS trg_ticket_del_enrichment_cleanup
AFTER DELETE ON tickets
BEGIN
  -- Hard deletes (row lifecycle ends with the ticket)
  DELETE FROM bench_timers            WHERE ticket_id = OLD.id;
  DELETE FROM qc_sign_offs            WHERE ticket_id = OLD.id;
  DELETE FROM warranty_certificates   WHERE ticket_id = OLD.id;
  DELETE FROM ticket_photos_visibility WHERE ticket_id = OLD.id;
  DELETE FROM ticket_handoffs         WHERE ticket_id = OLD.id;
  DELETE FROM team_mentions
    WHERE context_type = 'ticket_note' AND context_id = OLD.id;

  -- Cascade into chat messages before deleting channels so we don't leave
  -- orphan rows in team_chat_messages. Done as two statements instead of a
  -- subquery DELETE so the ordering is explicit to reviewers.
  DELETE FROM team_chat_messages
    WHERE channel_id IN (
      SELECT id FROM team_chat_channels
      WHERE kind = 'ticket' AND ticket_id = OLD.id
    );
  DELETE FROM team_chat_channels
    WHERE kind = 'ticket' AND ticket_id = OLD.id;

  -- Nullify on tables whose rows should outlive the ticket (audit / history)
  UPDATE parts_defect_reports       SET ticket_id = NULL WHERE ticket_id = OLD.id;
  UPDATE customer_reviews           SET ticket_id = NULL WHERE ticket_id = OLD.id;
  UPDATE nps_responses              SET ticket_id = NULL WHERE ticket_id = OLD.id;
  UPDATE inventory_serial_numbers   SET ticket_id = NULL WHERE ticket_id = OLD.id;
  UPDATE deposits                   SET ticket_id = NULL WHERE ticket_id = OLD.id;
END;

-- 6. Recreate trg_inventory_del_enrichment_cleanup verbatim from migration 097
--    so soft-delete admin jobs still cascade-cleanup enrichment tables when an
--    inventory_items row is purged. Same source-of-truth caveat as the
--    ticket trigger above.
CREATE TRIGGER IF NOT EXISTS trg_inventory_del_enrichment_cleanup
AFTER DELETE ON inventory_items
BEGIN
  DELETE FROM parts_defect_reports         WHERE inventory_item_id = OLD.id;
  DELETE FROM inventory_bin_assignments    WHERE inventory_item_id = OLD.id;
  DELETE FROM inventory_serial_numbers     WHERE inventory_item_id = OLD.id;
  DELETE FROM inventory_shrinkage          WHERE inventory_item_id = OLD.id;
  DELETE FROM supplier_prices              WHERE inventory_item_id = OLD.id;
  DELETE FROM supplier_returns             WHERE inventory_item_id = OLD.id;
  DELETE FROM inventory_compatibility      WHERE inventory_item_id = OLD.id;
  DELETE FROM inventory_lot_warranty       WHERE inventory_item_id = OLD.id;
  DELETE FROM inventory_auto_reorder_rules WHERE inventory_item_id = OLD.id;
  DELETE FROM stocktake_counts             WHERE inventory_item_id = OLD.id;
END;
