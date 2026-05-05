-- POS3 / POS payment tracking + EM6 employee tip tracking
--
-- Fixes:
--   POS3: payments table only stored the method name (TEXT). A POS sale that
--         went through a card terminal (BlockChyp) left no trace of which
--         processor, which auth ref, or which receipt reference — making it
--         impossible to reconcile or chargeback-trace. Adds `processor` and
--         `reference` columns. `processor_transaction_id` and
--         `processor_response` already exist from migration 040 (BlockChyp) but
--         there was no generic 'reference' field for non-BlockChyp processors
--         (Square, Stripe, manual card authorizations, etc).
--
--   EM6:  Tips were stored on pos_transactions.tip but never tied to the
--         cashier's employee record, so commission/tip-out reports had no data
--         to work with. Adds employee_tips table linking the tip to its owner.
--
-- Note: All columns use ALTER TABLE ADD COLUMN, which is idempotent only via
-- the migrations tracker. Since this migration runs once, the columns can be
-- added unconditionally.

-- ----------------------------------------------------------------------------
-- POS3: Payment processor + reference fields
-- ----------------------------------------------------------------------------
ALTER TABLE payments ADD COLUMN processor TEXT;
ALTER TABLE payments ADD COLUMN reference TEXT;

CREATE INDEX IF NOT EXISTS idx_payments_reference ON payments(reference);
CREATE INDEX IF NOT EXISTS idx_payments_processor ON payments(processor);

-- ----------------------------------------------------------------------------
-- EM6: Employee tip tracking
-- ----------------------------------------------------------------------------
-- One row per tip captured on a POS sale. tip_amount is stored in dollars as
-- REAL for consistency with invoices/payments; all POS writes should round via
-- roundCents() before insert. employee_id points at users(id) (cashiers are
-- users). invoice_id / pos_transaction_id let reporting roll tips up two ways.
CREATE TABLE IF NOT EXISTS employee_tips (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  employee_id       INTEGER NOT NULL REFERENCES users(id),
  invoice_id        INTEGER REFERENCES invoices(id),
  pos_transaction_id INTEGER REFERENCES pos_transactions(id),
  tip_amount        REAL NOT NULL DEFAULT 0,
  tip_method        TEXT,          -- 'cash' | 'card' | split-method tag
  created_at        TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at        TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_employee_tips_employee_id       ON employee_tips(employee_id);
CREATE INDEX IF NOT EXISTS idx_employee_tips_invoice_id        ON employee_tips(invoice_id);
CREATE INDEX IF NOT EXISTS idx_employee_tips_pos_transaction_id ON employee_tips(pos_transaction_id);
CREATE INDEX IF NOT EXISTS idx_employee_tips_created_at        ON employee_tips(created_at);

-- ----------------------------------------------------------------------------
-- POS7: Walk-in customer sentinel
-- ----------------------------------------------------------------------------
-- Creates a single special customer row used for walk-in POS sales where no
-- customer was selected. Keyed by a well-known code so application code can
-- look it up idempotently. customers.code has a UNIQUE constraint (001_initial)
-- so INSERT OR IGNORE makes this safe to run once.
INSERT OR IGNORE INTO customers (code, first_name, last_name, type, source, is_deleted, created_at, updated_at)
VALUES ('WALK-IN', 'Walk-in', 'Customer', 'individual', 'Walk-in', 0, datetime('now'), datetime('now'));
