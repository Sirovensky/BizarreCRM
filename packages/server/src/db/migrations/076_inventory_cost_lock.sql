-- S8 (pre-prod audit): cost_locked flag on inventory items.
-- When set to 1, supplier catalog sync + catalog-driven updates must NOT
-- overwrite cost_price. Use this for items where the ops team has negotiated
-- a fixed cost or wants to protect a manual override from being clobbered
-- by the next scraped catalog pass.
--
-- Cost-price history (migration 059_cost_price_history.sql) still records
-- every change, but catalog sync callers are expected to short-circuit when
-- this column is 1.
ALTER TABLE inventory_items ADD COLUMN cost_locked INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_inventory_items_cost_locked
  ON inventory_items(cost_locked) WHERE cost_locked = 1;
