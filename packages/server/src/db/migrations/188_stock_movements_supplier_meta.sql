-- Migration 188 — WEB-UIUX-1189: capture receiving metadata so AP matching
-- + lot/expiry traceability work without falling back to free-text notes.
-- All columns are nullable so legacy receives (`notes='Received from PO'`)
-- continue to validate; new receives may pass any subset.
ALTER TABLE stock_movements ADD COLUMN supplier_invoice_no TEXT;
ALTER TABLE stock_movements ADD COLUMN packing_slip_no TEXT;
ALTER TABLE stock_movements ADD COLUMN lot_number TEXT;
ALTER TABLE stock_movements ADD COLUMN expiration_date TEXT;
ALTER TABLE stock_movements ADD COLUMN bin_location TEXT;
ALTER TABLE stock_movements ADD COLUMN actual_unit_cost_cents INTEGER;

CREATE INDEX IF NOT EXISTS idx_stock_movements_supplier_invoice
  ON stock_movements(supplier_invoice_no) WHERE supplier_invoice_no IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_stock_movements_lot
  ON stock_movements(lot_number) WHERE lot_number IS NOT NULL;
