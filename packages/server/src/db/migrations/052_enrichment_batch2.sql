-- 052_enrichment_batch2.sql
-- Batch 2 enrichment features: leads, estimates, invoices, tickets, POs, appointments

-- ENR-LE7: Estimate read receipt — track when customer first views an estimate
ALTER TABLE estimates ADD COLUMN viewed_at TEXT;

-- ENR-LE12: Recurring appointments — recurrence pattern on appointments
ALTER TABLE appointments ADD COLUMN recurrence TEXT CHECK(recurrence IS NULL OR recurrence IN ('weekly', 'biweekly', 'monthly'));
ALTER TABLE appointments ADD COLUMN recurrence_parent_id INTEGER REFERENCES appointments(id);

-- ENR-I8: Payment plan tracking on invoices
ALTER TABLE invoices ADD COLUMN payment_plan TEXT;

-- ENR-POS1: Layaway support on tickets
ALTER TABLE tickets ADD COLUMN is_layaway INTEGER NOT NULL DEFAULT 0;
ALTER TABLE tickets ADD COLUMN layaway_expires TEXT;

-- ENR-INV7: PO delivery tracking — actual_received_date
-- expected_date already exists from PO creation; add actual_received_date
ALTER TABLE purchase_orders ADD COLUMN actual_received_date TEXT;
