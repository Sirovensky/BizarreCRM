-- PERF-6: Index for COGS report supplier_catalog name matching
-- The COGS query does LOWER(TRIM(sc.name)) on every row in a correlated subquery.
-- This expression index lets SQLite use an index scan instead of a full table scan.
CREATE INDEX IF NOT EXISTS idx_supplier_catalog_name_lower
  ON supplier_catalog(LOWER(TRIM(name)));

-- Also index on price > 0 filter used in COGS lookup
CREATE INDEX IF NOT EXISTS idx_supplier_catalog_name_price
  ON supplier_catalog(LOWER(TRIM(name)), price)
  WHERE price > 0;

-- PERF-7: Index for NOT EXISTS payments lookup in revenue queries
-- payments(invoice_id) already indexed in 053, but add covering index
-- that includes the id column for faster EXISTS checks
CREATE INDEX IF NOT EXISTS idx_payments_invoice_covering
  ON payments(invoice_id, id);

-- PERF-9: Indexes for customer stats correlated subqueries
-- These run when include_stats=1 on customer list
CREATE INDEX IF NOT EXISTS idx_invoices_customer_status
  ON invoices(customer_id, status);
CREATE INDEX IF NOT EXISTS idx_invoices_customer_total
  ON invoices(customer_id, status, total);
