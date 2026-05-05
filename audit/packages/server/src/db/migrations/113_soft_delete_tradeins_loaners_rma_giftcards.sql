-- SEC-H121 (LOGIC-019): Soft-delete audit trail for trade_ins, loaner_devices,
-- rma_requests, and gift_cards.  Hard DELETEs on these tables destroy the
-- audit trail; soft-delete keeps the row while hiding it from all normal
-- list/detail queries via `AND is_deleted = 0` guards in the route layer.
--
-- Columns added to each table:
--   is_deleted        INTEGER NOT NULL DEFAULT 0   — 0 = live, 1 = soft-deleted
--   deleted_at        TEXT                          — datetime('now') at delete time
--   deleted_by_user_id INTEGER                     — FK to users(id), who deleted it
--
-- Partial indexes on is_deleted = 0 are added for columns used in common
-- list/lookup queries so the query planner can use the index directly without
-- scanning deleted rows.

-- ============================================================
-- trade_ins
-- ============================================================
ALTER TABLE trade_ins ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;
ALTER TABLE trade_ins ADD COLUMN deleted_at TEXT;
ALTER TABLE trade_ins ADD COLUMN deleted_by_user_id INTEGER REFERENCES users(id);

-- Partial index on customer_id (list-by-customer) and status (list-by-status)
CREATE INDEX IF NOT EXISTS idx_trade_ins_customer_active
  ON trade_ins(customer_id) WHERE is_deleted = 0;
CREATE INDEX IF NOT EXISTS idx_trade_ins_status_active
  ON trade_ins(status) WHERE is_deleted = 0;
CREATE INDEX IF NOT EXISTS idx_trade_ins_created_active
  ON trade_ins(created_at DESC) WHERE is_deleted = 0;

-- ============================================================
-- loaner_devices
-- ============================================================
ALTER TABLE loaner_devices ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;
ALTER TABLE loaner_devices ADD COLUMN deleted_at TEXT;
ALTER TABLE loaner_devices ADD COLUMN deleted_by_user_id INTEGER REFERENCES users(id);

-- Partial index on name (ordered list) and status (availability filter)
CREATE INDEX IF NOT EXISTS idx_loaner_devices_name_active
  ON loaner_devices(name) WHERE is_deleted = 0;
CREATE INDEX IF NOT EXISTS idx_loaner_devices_status_active
  ON loaner_devices(status) WHERE is_deleted = 0;

-- ============================================================
-- rma_requests
-- ============================================================
ALTER TABLE rma_requests ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;
ALTER TABLE rma_requests ADD COLUMN deleted_at TEXT;
ALTER TABLE rma_requests ADD COLUMN deleted_by_user_id INTEGER REFERENCES users(id);

-- Partial index on supplier_id and status (common list filters)
CREATE INDEX IF NOT EXISTS idx_rma_requests_supplier_active
  ON rma_requests(supplier_id) WHERE is_deleted = 0;
CREATE INDEX IF NOT EXISTS idx_rma_requests_status_active
  ON rma_requests(status) WHERE is_deleted = 0;
CREATE INDEX IF NOT EXISTS idx_rma_requests_created_active
  ON rma_requests(created_at DESC) WHERE is_deleted = 0;

-- ============================================================
-- gift_cards
-- ============================================================
ALTER TABLE gift_cards ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;
ALTER TABLE gift_cards ADD COLUMN deleted_at TEXT;
ALTER TABLE gift_cards ADD COLUMN deleted_by_user_id INTEGER REFERENCES users(id);

-- Partial index on code_hash (lookup path) and customer_id / status (list)
CREATE INDEX IF NOT EXISTS idx_gift_cards_code_hash_active
  ON gift_cards(code_hash) WHERE is_deleted = 0;
CREATE INDEX IF NOT EXISTS idx_gift_cards_status_active
  ON gift_cards(status) WHERE is_deleted = 0;
CREATE INDEX IF NOT EXISTS idx_gift_cards_customer_active
  ON gift_cards(customer_id) WHERE is_deleted = 0;
