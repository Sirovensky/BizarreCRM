-- SCAN-1082: SQLite treats every NULL as distinct inside a UNIQUE
-- constraint, so `UNIQUE(source, external_id)` on supplier_catalog only
-- dedup's rows that actually have an external_id. Scraped sources
-- occasionally return PDP rows without a supplier product id — every
-- re-scrape of such a row INSERTs a new row, and the scraper's
-- "upsert by external_id" assumption silently becomes "append forever".
--
-- Fix: add a partial unique index on (source, name) for the NULL-id path
-- so repeated scrapes of the same nameless product dedup by name. Rows
-- with an external_id keep using the existing UNIQUE(source, external_id).
-- The two covering indexes are disjoint (WHERE clauses), so they never
-- conflict.
CREATE UNIQUE INDEX IF NOT EXISTS ux_supplier_catalog_source_name_null_ext
  ON supplier_catalog (source, name)
  WHERE external_id IS NULL;
