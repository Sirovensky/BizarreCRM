-- ============================================================================
-- 087 — Device-model repair templates (audit section 44.1, cross-cutting)
-- ============================================================================
--
-- Audit 44.1:
--   "pick 'iPhone 13 screen repair' -> auto-populates parts, labor, est. time,
--    diagnostic checklist."
--
-- Cross-cutting rationale:
--   This table is also referenced from POS (section 43) and Inventory (48)
--   as the single source of truth for a canonical "repair job". A tech on a
--   ticket, a cashier ringing up a walk-in repair on POS, and a stock report
--   all need to know: "for iPhone 13 screen replacement, what parts are used
--   and what should we charge?". Keeping this in one table (instead of three
--   copies per domain) is the whole point of migration 087.
--
-- Shape:
--   parts_json stores a JSON array of { inventory_item_id, qty } so the tech
--   gets a one-click apply. We do NOT hard-FK each row into a junction table
--   because template editing on the admin page should be a single UPDATE
--   statement, not N deletes + N inserts.
--
-- Pricing is in integer cents everywhere to match invoices/POS.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS device_model_templates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,                             -- "iPhone 13 Screen Replacement"
  device_category TEXT,                           -- "phone" | "tablet" | "laptop" | "tv" | "watch" | "other"
  device_model TEXT,                              -- "iPhone 13"
  fault TEXT,                                     -- "screen" | "battery" | "water damage" | ...
  est_labor_minutes INTEGER NOT NULL DEFAULT 0,
  est_labor_cost INTEGER NOT NULL DEFAULT 0,      -- cents
  suggested_price INTEGER NOT NULL DEFAULT 0,     -- cents — customer-facing quote
  diagnostic_checklist_json TEXT,                 -- JSON array of checklist step names
  parts_json TEXT,                                -- JSON array of {inventory_item_id, qty}
  warranty_days INTEGER NOT NULL DEFAULT 30,
  is_active INTEGER NOT NULL DEFAULT 1,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_device_templates_category
  ON device_model_templates(device_category, is_active);

CREATE INDEX IF NOT EXISTS idx_device_templates_model
  ON device_model_templates(device_model, fault, is_active);

-- Feature flag: whether templates are surfaced in the ticket UI at all.
-- Shops that prefer free-form data entry can hide the picker.
INSERT OR IGNORE INTO store_config (key, value) VALUES
  ('device_templates_enabled', 'true');
