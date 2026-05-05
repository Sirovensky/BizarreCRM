-- SC5 (pre-prod audit): Audit trail for supplier catalog price overwrites.
-- Every time a scraper / bulk import rewrites an existing row in
-- supplier_catalog we record the old price into this table so operators can
-- recover from a bad sync pass (bad supplier HTML, malformed prices, etc.).
--
-- Also used by the inventory-side syncCostPricesFromCatalog() flow as a
-- hook point for future diffing.

CREATE TABLE IF NOT EXISTS catalog_price_history (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  supplier_catalog_id  INTEGER NOT NULL REFERENCES supplier_catalog(id) ON DELETE CASCADE,
  source               TEXT NOT NULL,
  external_id          TEXT,
  sku                  TEXT,
  name                 TEXT,
  old_price            REAL,
  new_price            REAL NOT NULL,
  change_source        TEXT NOT NULL DEFAULT 'scrape', -- scrape | bulk_import | manual
  job_id               INTEGER,                        -- scrape_jobs.id when applicable
  created_at           TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_catalog_price_history_catalog
  ON catalog_price_history(supplier_catalog_id);
CREATE INDEX IF NOT EXISTS idx_catalog_price_history_created
  ON catalog_price_history(created_at);

-- SC1: Unique partial index enforcing at-most-one "running" sync per source.
-- scrape_jobs.status in ('pending','running') should be singular per source
-- so concurrent /sync requests cannot both slip past the SELECT-then-INSERT
-- gate. Use a partial unique index over the filter column.
CREATE UNIQUE INDEX IF NOT EXISTS idx_scrape_jobs_single_running
  ON scrape_jobs(source)
  WHERE status IN ('pending', 'running');

-- SC2: New failure mode columns for richer status tracking.
-- total_attempts = how many (query, page) pairs we tried
-- successful_items = how many rows actually upserted
-- errors_json = JSON array of { query, page, message } for debugging
ALTER TABLE scrape_jobs ADD COLUMN total_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE scrape_jobs ADD COLUMN successful_items INTEGER NOT NULL DEFAULT 0;
ALTER TABLE scrape_jobs ADD COLUMN errors_json TEXT;
