-- 053: Production performance indexes
-- ENR-DB5 through ENR-DB8 plus additional high-value indexes

-- ENR-DB5: SMS messages time-range queries
CREATE INDEX IF NOT EXISTS idx_sms_messages_created ON sms_messages(created_at);
-- ENR-DB6: Invoice status filtering
CREATE INDEX IF NOT EXISTS idx_invoices_status ON invoices(status);
-- ENR-DB7: Ticket devices common query pattern
CREATE INDEX IF NOT EXISTS idx_ticket_devices_ticket_status ON ticket_devices(ticket_id, status_id);
-- ENR-DB8: Store credit lookups
CREATE INDEX IF NOT EXISTS idx_store_credit_txn_customer ON store_credit_transactions(customer_id);
-- Additional production indexes
CREATE INDEX IF NOT EXISTS idx_payments_invoice ON payments(invoice_id);
CREATE INDEX IF NOT EXISTS idx_ticket_notes_ticket ON ticket_notes(ticket_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON audit_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone);
CREATE INDEX IF NOT EXISTS idx_customers_mobile ON customers(mobile);
