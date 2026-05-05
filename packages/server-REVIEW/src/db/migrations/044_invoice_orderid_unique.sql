-- AUD-M74: Add UNIQUE constraint on invoices.order_id to prevent duplicate order IDs
CREATE UNIQUE INDEX IF NOT EXISTS idx_invoices_order_id_unique ON invoices(order_id);
