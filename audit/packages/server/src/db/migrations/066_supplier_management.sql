-- ENR-INV5: Supplier management enhancements
-- Add missing columns to existing suppliers table
ALTER TABLE suppliers ADD COLUMN website TEXT;
ALTER TABLE suppliers ADD COLUMN rating INTEGER CHECK(rating BETWEEN 1 AND 5);
ALTER TABLE suppliers ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1;

-- Link inventory items to preferred suppliers
ALTER TABLE inventory_items ADD COLUMN preferred_supplier_id INTEGER REFERENCES suppliers(id);
