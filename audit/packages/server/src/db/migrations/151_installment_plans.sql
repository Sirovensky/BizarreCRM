-- Migration 151: installment_plans + installment_schedule tables (WEB-W2-002)
-- Allows a balance to be split into N periodic payments with an explicit
-- customer acceptance token captured at plan creation time.

CREATE TABLE IF NOT EXISTS installment_plans (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_id           INTEGER REFERENCES invoices(id) ON DELETE SET NULL,
  customer_id          INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  total_cents          INTEGER NOT NULL CHECK (total_cents > 0),
  installment_count    INTEGER NOT NULL CHECK (installment_count BETWEEN 2 AND 120),
  frequency_days       INTEGER NOT NULL CHECK (frequency_days BETWEEN 1 AND 365),
  -- Typed customer signature captured before any auto-debit can fire.
  acceptance_token     TEXT    NOT NULL,
  acceptance_signed_at TEXT    NOT NULL,
  status               TEXT    NOT NULL DEFAULT 'active'
                                CHECK (status IN ('active', 'completed', 'cancelled')),
  created_at           TEXT    NOT NULL DEFAULT (datetime('now')),
  updated_at           TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS installment_schedule (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  plan_id     INTEGER NOT NULL REFERENCES installment_plans(id) ON DELETE CASCADE,
  due_date    TEXT    NOT NULL,          -- YYYY-MM-DD
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  status      TEXT    NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending', 'paid', 'overdue', 'waived')),
  paid_at     TEXT,
  created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- Indexes used by the route's list + FK-lookup queries
CREATE INDEX IF NOT EXISTS idx_installment_plans_invoice_id   ON installment_plans(invoice_id);
CREATE INDEX IF NOT EXISTS idx_installment_plans_customer_id  ON installment_plans(customer_id);
CREATE INDEX IF NOT EXISTS idx_installment_plans_status       ON installment_plans(status);
CREATE INDEX IF NOT EXISTS idx_installment_schedule_plan_id   ON installment_schedule(plan_id);
CREATE INDEX IF NOT EXISTS idx_installment_schedule_due_date  ON installment_schedule(due_date);
