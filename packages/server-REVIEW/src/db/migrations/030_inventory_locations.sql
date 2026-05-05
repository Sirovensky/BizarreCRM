-- Add location tracking to inventory
ALTER TABLE inventory_items ADD COLUMN location TEXT DEFAULT '';
ALTER TABLE inventory_items ADD COLUMN shelf TEXT DEFAULT '';
ALTER TABLE inventory_items ADD COLUMN bin TEXT DEFAULT '';
