-- Performance indexes identified during comprehensive audit

-- Ticket device parts: faster device-part lookups and cascading deletes
CREATE INDEX IF NOT EXISTS idx_ticket_device_parts_device ON ticket_device_parts(ticket_device_id);

-- Tickets: composite index for common sort patterns (pinned + date)
CREATE INDEX IF NOT EXISTS idx_tickets_pinned_created ON tickets(is_pinned DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tickets_pinned_updated ON tickets(is_pinned DESC, updated_at DESC);

-- Invoices: faster payment status lookups for reports
CREATE INDEX IF NOT EXISTS idx_invoices_status_date ON invoices(status, created_at);

-- Ticket notes: faster latest-note subqueries
CREATE INDEX IF NOT EXISTS idx_ticket_notes_ticket_type_date ON ticket_notes(ticket_id, type, created_at DESC);
