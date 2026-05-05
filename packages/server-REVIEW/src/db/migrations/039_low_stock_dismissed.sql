-- Track when low stock alert was dismissed for an item
-- It will reappear if stock drops again after being restocked
ALTER TABLE inventory_items ADD COLUMN low_stock_dismissed_at TEXT;
