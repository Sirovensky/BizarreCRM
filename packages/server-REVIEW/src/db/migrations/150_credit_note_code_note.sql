-- Migration 150: add structured code + note columns to credit-note invoices
-- Credit notes are stored as negative invoices in the `invoices` table.
-- The UI sends a typed RefundReasonCode (`code`) plus a free-text (`note`)
-- but the route previously packed them into the composed `reason` string
-- stored in invoice_line_items.notes. Store them directly so reports can
-- GROUP BY refund reason code without string parsing.

ALTER TABLE invoices ADD COLUMN credit_note_code TEXT;
ALTER TABLE invoices ADD COLUMN credit_note_note TEXT;
