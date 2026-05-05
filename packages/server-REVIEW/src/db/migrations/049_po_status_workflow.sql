-- ─────────────────────────────────────────────────────────────────────────────
-- 049: PO status workflow — expand purchase_orders with richer status tracking
-- ─────────────────────────────────────────────────────────────────────────────

-- Add tracking fields for PO status workflow
ALTER TABLE purchase_orders ADD COLUMN ordered_date TEXT;
ALTER TABLE purchase_orders ADD COLUMN cancelled_date TEXT;
ALTER TABLE purchase_orders ADD COLUMN cancelled_reason TEXT;

-- Add desired_stock_level to inventory_items for auto-reorder calculation
ALTER TABLE inventory_items ADD COLUMN desired_stock_level INTEGER NOT NULL DEFAULT 0;
