-- 1. Add "Created" status as the new default (sort_order 0, before everything)
INSERT OR IGNORE INTO ticket_statuses (name, color, sort_order, is_default, is_closed, notify_customer)
VALUES ('Created', '#60a5fa', 0, 1, 0, 0);

-- 2. Remove default flag from "Waiting for inspection"
UPDATE ticket_statuses SET is_default = 0 WHERE name = 'Waiting for inspection';

-- 3. Rename "Open" to "On Hold"
UPDATE ticket_statuses SET name = 'On Hold', color = '#6b7280' WHERE id = 1 AND name = 'Open';

-- 4. Shift sort orders so Created=0, Waiting for inspection=1, etc.
UPDATE ticket_statuses SET sort_order = sort_order + 1 WHERE name != 'Created' AND sort_order >= 0;

-- 5. Ensure Created has sort_order 0
UPDATE ticket_statuses SET sort_order = 0 WHERE name = 'Created';

-- 6. Add is_reorderable column to inventory_items (default false)
--    Only PLP/MS supplier parts should be reorderable
ALTER TABLE inventory_items ADD COLUMN is_reorderable INTEGER NOT NULL DEFAULT 0;

-- 7. Mark items linked to known suppliers as reorderable
--    Supplier names containing 'Mobilesentrix' or 'PhoneLcdParts' or 'PLP'
UPDATE inventory_items SET is_reorderable = 1
WHERE supplier_id IN (
  SELECT id FROM suppliers WHERE
    LOWER(name) LIKE '%mobilesentrix%' OR
    LOWER(name) LIKE '%phonelcdparts%' OR
    LOWER(name) LIKE '%plp%' OR
    LOWER(name) LIKE '%mobile sentrix%'
);

-- Also mark items that came from supplier catalog (have a catalog link)
UPDATE inventory_items SET is_reorderable = 1
WHERE id IN (
  SELECT inventory_item_id FROM inventory_device_compatibility
  WHERE inventory_item_id IS NOT NULL
) OR id IN (
  SELECT ii.id FROM inventory_items ii
  JOIN supplier_catalog sc ON LOWER(ii.name) = LOWER(sc.name)
  WHERE sc.source IN ('mobilesentrix', 'phonelcdparts')
);
