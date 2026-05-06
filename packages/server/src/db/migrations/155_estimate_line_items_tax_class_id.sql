-- Migration 155: persist tax class selections on estimate line items.
-- The web estimate form already sends tax_class_id per line so converted
-- tickets/invoices can preserve the tax basis. Store it instead of reducing
-- the choice to a precomputed tax_amount only.

ALTER TABLE estimate_line_items ADD COLUMN tax_class_id INTEGER REFERENCES tax_classes(id);
