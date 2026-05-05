-- ENR-I2: Deposit + balance workflow
-- Allows creating deposit invoices at drop-off, then final invoices at pickup referencing the deposit.
ALTER TABLE invoices ADD COLUMN is_deposit INTEGER NOT NULL DEFAULT 0;
ALTER TABLE invoices ADD COLUMN parent_invoice_id INTEGER REFERENCES invoices(id);
ALTER TABLE invoices ADD COLUMN deposit_amount REAL NOT NULL DEFAULT 0;
