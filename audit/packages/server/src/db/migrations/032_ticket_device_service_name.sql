-- Add service_name column to ticket_devices so the human-readable name is stored directly
ALTER TABLE ticket_devices ADD COLUMN service_name TEXT;

-- Backfill from inventory_items where service_id is set
UPDATE ticket_devices
SET service_name = (
  SELECT ii.name FROM inventory_items ii WHERE ii.id = ticket_devices.service_id
)
WHERE service_id IS NOT NULL AND service_name IS NULL;
