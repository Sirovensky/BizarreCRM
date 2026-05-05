-- SEC-H37: Add `currency` TEXT column to every money-bearing table,
-- default 'USD'. Single-currency tenants continue to operate without
-- reading the column; multi-currency support (FX conversion, reporting
-- by currency, etc.) builds on this column later.
--
-- Columns kept narrow (3-char ISO 4217 code) + indexed on tables that
-- are likely to get per-currency reports. The SQLite-wide convention
-- elsewhere in this repo is to add columns idempotently via ALTER
-- TABLE in a separate migration, not CREATE TABLE rewrites.
--
-- Blocks SEC-H34-money-refactor (REAL → INTEGER cents) — when that
-- lands we'll ship cents + currency together so reporting knows
-- which minor-unit denomination it's reading.

ALTER TABLE invoices   ADD COLUMN currency TEXT NOT NULL DEFAULT 'USD';
ALTER TABLE payments   ADD COLUMN currency TEXT NOT NULL DEFAULT 'USD';
ALTER TABLE refunds    ADD COLUMN currency TEXT NOT NULL DEFAULT 'USD';
ALTER TABLE gift_cards ADD COLUMN currency TEXT NOT NULL DEFAULT 'USD';
ALTER TABLE deposits   ADD COLUMN currency TEXT NOT NULL DEFAULT 'USD';
ALTER TABLE pos_transactions ADD COLUMN currency TEXT NOT NULL DEFAULT 'USD';

CREATE INDEX IF NOT EXISTS idx_invoices_currency  ON invoices(currency);
CREATE INDEX IF NOT EXISTS idx_payments_currency  ON payments(currency);
CREATE INDEX IF NOT EXISTS idx_refunds_currency   ON refunds(currency);
