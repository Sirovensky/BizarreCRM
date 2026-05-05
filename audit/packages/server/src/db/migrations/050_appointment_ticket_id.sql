-- Add ticket_id to appointments so appointments can be linked to tickets
ALTER TABLE appointments ADD COLUMN ticket_id INTEGER REFERENCES tickets(id);
CREATE INDEX IF NOT EXISTS idx_appointments_ticket_id ON appointments(ticket_id);
