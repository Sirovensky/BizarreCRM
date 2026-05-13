-- WEB-UIUX-765: per-customer tax-exempt flag.
-- Non-profit / reseller / govt customers should have every cart line auto
-- flip taxable=0; today the cashier has to remember per line. Schema-only
-- step; POS auto-apply logic + server-side enforcement at invoice creation
-- ride a follow-up. tax_exempt_reason stays text (free-form) so the
-- operator can paste a resale certificate id or state exemption number.
ALTER TABLE customers ADD COLUMN tax_exempt INTEGER NOT NULL DEFAULT 0
  CHECK (tax_exempt IN (0, 1));
ALTER TABLE customers ADD COLUMN tax_exempt_reason TEXT;

CREATE INDEX IF NOT EXISTS idx_customers_tax_exempt
  ON customers(tax_exempt) WHERE tax_exempt = 1;
