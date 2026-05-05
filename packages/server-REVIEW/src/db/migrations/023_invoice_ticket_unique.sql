-- Prevent double-conversion: one ticket can only have one invoice
CREATE UNIQUE INDEX IF NOT EXISTS idx_invoices_ticket_unique ON invoices(ticket_id) WHERE ticket_id IS NOT NULL;
