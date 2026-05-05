-- AUD-M75: Add index on ticket_device_parts.status for faster missing-parts queries
CREATE INDEX IF NOT EXISTS idx_ticket_device_parts_status ON ticket_device_parts(status);
