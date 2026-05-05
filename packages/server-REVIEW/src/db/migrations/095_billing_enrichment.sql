-- ============================================================================
-- Migration 095 — Billing / Money Flow enrichment (audit §52)
-- ============================================================================
--
-- Purely additive. Creates schema for:
--   1. Payment-link portal (Stripe-hosted, trackable)
--   2. Installment plans + per-installment schedule
--   3. Dunning sequences and run-history
--   4. Deposit workflow (drop-off → apply to final invoice)
--
-- All money is stored in INTEGER cents (matches §52 convention). Dollar
-- amounts live only in the UI.  No existing tables are modified.
-- ============================================================================

-- ── 1. Payment links ────────────────────────────────────────────────────────
-- A customer-facing tokenized URL used to collect payment for an invoice
-- without requiring a login.  `token` is high-entropy (generated in route),
-- so it doubles as the auth credential for the public /pay/:token page.
CREATE TABLE IF NOT EXISTS payment_links (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  token                TEXT NOT NULL UNIQUE,
  invoice_id           INTEGER,
  customer_id          INTEGER,
  amount_cents         INTEGER NOT NULL,
  description          TEXT,
  provider             TEXT NOT NULL DEFAULT 'stripe', -- 'stripe' | 'blockchyp'
  status               TEXT NOT NULL DEFAULT 'active'
                         CHECK (status IN ('active','paid','expired','cancelled')),
  paid_at              TEXT,
  click_count          INTEGER NOT NULL DEFAULT 0,
  last_clicked_at      TEXT,
  expires_at           TEXT,
  created_at           TEXT NOT NULL DEFAULT (datetime('now')),
  created_by_user_id   INTEGER
);
CREATE INDEX IF NOT EXISTS idx_payment_links_status   ON payment_links(status);
CREATE INDEX IF NOT EXISTS idx_payment_links_invoice  ON payment_links(invoice_id);
CREATE INDEX IF NOT EXISTS idx_payment_links_customer ON payment_links(customer_id);

-- ── 2. Installment plans ────────────────────────────────────────────────────
-- A plan is the "contract" ("split $500 into 4 weekly payments").
-- Acceptance token + signed_at captures the BlockChyp safety requirement —
-- no auto-debit can fire until the customer has explicitly opted in.
CREATE TABLE IF NOT EXISTS installment_plans (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_id            INTEGER,
  customer_id           INTEGER NOT NULL,
  total_cents           INTEGER NOT NULL,
  installment_count     INTEGER NOT NULL,
  frequency_days        INTEGER NOT NULL,
  acceptance_token      TEXT,
  acceptance_signed_at  TEXT,
  status                TEXT NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending','active','completed','defaulted','cancelled')),
  created_at            TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_installment_plans_customer ON installment_plans(customer_id);
CREATE INDEX IF NOT EXISTS idx_installment_plans_status   ON installment_plans(status);

-- Per-installment rows are created when the plan is materialized (inside a
-- transaction in the route handler).  `charged_at` / `transaction_ref` stay
-- NULL until an actual charge succeeds.
CREATE TABLE IF NOT EXISTS installment_schedule (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  plan_id          INTEGER NOT NULL,
  due_date         TEXT NOT NULL,
  amount_cents     INTEGER NOT NULL,
  status           TEXT NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending','paid','failed','skipped')),
  charged_at       TEXT,
  transaction_ref  TEXT
);
CREATE INDEX IF NOT EXISTS idx_installment_schedule_plan ON installment_schedule(plan_id);
CREATE INDEX IF NOT EXISTS idx_installment_schedule_due  ON installment_schedule(due_date);

-- ── 3. Dunning sequences ────────────────────────────────────────────────────
-- Template for a multi-step overdue-invoice follow-up.  steps_json stores a
-- JSON array of { days_offset, action, template_id }.  The scheduler walks
-- this each day to decide who gets what reminder.
CREATE TABLE IF NOT EXISTS dunning_sequences (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  name         TEXT NOT NULL,
  is_active    INTEGER NOT NULL DEFAULT 1,
  steps_json   TEXT NOT NULL,
  created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

-- dunning_runs records which invoice received which step of which sequence.
-- The UNIQUE constraint makes the scheduler idempotent — a restart or
-- duplicate cron tick cannot double-send a reminder.
CREATE TABLE IF NOT EXISTS dunning_runs (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_id   INTEGER NOT NULL,
  sequence_id  INTEGER NOT NULL,
  step_index   INTEGER NOT NULL,
  executed_at  TEXT NOT NULL DEFAULT (datetime('now')),
  outcome      TEXT,  -- 'sent' | 'failed' | 'skipped'
  UNIQUE(invoice_id, sequence_id, step_index)
);
CREATE INDEX IF NOT EXISTS idx_dunning_runs_invoice ON dunning_runs(invoice_id);

-- Seed a single "default" sequence so the UI has something to show on day 1.
-- Day 0 invoice email is not a step here — the first *reminder* is day 3.
INSERT OR IGNORE INTO dunning_sequences (id, name, is_active, steps_json)
VALUES (
  1,
  'Default 3/10/20',
  1,
  '[{"days_offset":3,"action":"email","template_id":"overdue_reminder_1"},{"days_offset":10,"action":"sms","template_id":"overdue_reminder_2"},{"days_offset":20,"action":"escalate","template_id":"overdue_escalation"}]'
);

-- ── 4. Deposits ─────────────────────────────────────────────────────────────
-- Collected at repair drop-off.  `applied_to_invoice_id` is filled when the
-- tech finalizes the final invoice, which should subtract this amount from
-- the balance due.  `refunded_at` lets us keep history if the customer walks.
CREATE TABLE IF NOT EXISTS deposits (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id             INTEGER,
  customer_id           INTEGER NOT NULL,
  amount_cents          INTEGER NOT NULL,
  collected_at          TEXT NOT NULL DEFAULT (datetime('now')),
  applied_to_invoice_id INTEGER,
  applied_at            TEXT,
  refunded_at           TEXT,
  notes                 TEXT
);
CREATE INDEX IF NOT EXISTS idx_deposits_customer ON deposits(customer_id);
CREATE INDEX IF NOT EXISTS idx_deposits_ticket   ON deposits(ticket_id);
CREATE INDEX IF NOT EXISTS idx_deposits_applied  ON deposits(applied_to_invoice_id);

-- ── 5. Store config toggles ─────────────────────────────────────────────────
INSERT OR IGNORE INTO store_config (key, value) VALUES
  ('billing_qr_on_receipts',     '1'),
  ('billing_financing_enabled',  '0'),
  ('billing_financing_min_cents','50000'),
  ('billing_dunning_enabled',    '1');
