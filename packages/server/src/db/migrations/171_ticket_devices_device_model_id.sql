-- Migration 171: Add device_model_id FK to ticket_devices.
--
-- Routes (tickets.routes.ts, repairPricing.routes.ts) and the matrix-hot-sort
-- query already reference ticket_devices.device_model_id, but the column was
-- never added — every INSERT and the GET /repair-pricing/matrix endpoint
-- 500s with "no such column: device_model_id". This wires the FK so the POS
-- repair-intake flow can record which catalog device a ticket was opened
-- against, enabling per-model pricing and the "hot in the last 30 days"
-- filter on the matrix.
--
-- Old rows stay NULL (no reliable mapping from free-text device_name back to
-- a specific device_models row); new intakes fill it from RepairDraft.deviceModelId.

ALTER TABLE ticket_devices ADD COLUMN device_model_id INTEGER REFERENCES device_models(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_ticket_devices_device_model
  ON ticket_devices(device_model_id)
  WHERE device_model_id IS NOT NULL;
