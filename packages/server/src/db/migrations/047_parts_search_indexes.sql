-- Composite indexes for parts search performance
-- Helps LIKE queries by narrowing scan to active items first
CREATE INDEX IF NOT EXISTS idx_inventory_items_active_type
  ON inventory_items(is_active, item_type);

-- Supplier catalog search indexes
CREATE INDEX IF NOT EXISTS idx_supplier_catalog_source_name
  ON supplier_catalog(source, name);

-- Device compatibility lookup
CREATE INDEX IF NOT EXISTS idx_catalog_device_compat_device_catalog
  ON catalog_device_compatibility(device_model_id, supplier_catalog_id);

CREATE INDEX IF NOT EXISTS idx_inventory_device_compat_device_inv
  ON inventory_device_compatibility(device_model_id, inventory_item_id);
