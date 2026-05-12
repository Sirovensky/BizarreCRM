-- Migration 192 — WEB-UIUX-895: point-in-time snapshot columns on invoices
-- so a reprint 6 months later doesn't lie about the customer's renamed
-- profile, the store's renamed banner, or a tax-rate that's since shifted.
-- All columns are nullable — writers fill them at create time. Print pages
-- fall back to the live customer/store row when these are NULL (legacy
-- invoices pre-migration stay readable).
ALTER TABLE invoices ADD COLUMN customer_name_snapshot TEXT;
ALTER TABLE invoices ADD COLUMN customer_address_snapshot TEXT;
ALTER TABLE invoices ADD COLUMN store_name_snapshot TEXT;
ALTER TABLE invoices ADD COLUMN tax_jurisdiction_snapshot TEXT;
