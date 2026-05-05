-- =============================================================================
-- Migration 123 — Recurring Invoices + Credit Notes
-- =============================================================================
-- Additive only. Creates:
--   1. invoice_templates   — the recurring schedule definition
--   2. invoice_template_runs — per-fire audit history
--   3. credit_notes        — standalone credit notes (apply / void)
-- =============================================================================

-- ── 1. Invoice templates (recurring schedules) ───────────────────────────────

CREATE TABLE IF NOT EXISTS invoice_templates (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  name                TEXT    NOT NULL CHECK(length(name) <= 200),
  customer_id         INTEGER NOT NULL REFERENCES customers(id),
  interval_kind       TEXT    NOT NULL CHECK(interval_kind IN ('daily','weekly','monthly','yearly')),
  interval_count      INTEGER NOT NULL CHECK(interval_count > 0),
  start_date          TEXT    NOT NULL,   -- ISO YYYY-MM-DD
  next_run_at         TEXT    NOT NULL,   -- ISO datetime
  last_run_at         TEXT,              -- NULL until first run
  status              TEXT    NOT NULL DEFAULT 'active'
                              CHECK(status IN ('active','paused','canceled')),
  line_items_json     TEXT    NOT NULL,  -- JSON array of line item objects
  notes_template      TEXT    CHECK(notes_template IS NULL OR length(notes_template) <= 2000),
  tax_class_id        INTEGER REFERENCES tax_classes(id),
  created_by_user_id  INTEGER NOT NULL REFERENCES users(id),
  created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
  updated_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_invoice_templates_status_next
  ON invoice_templates(status, next_run_at);

CREATE INDEX IF NOT EXISTS idx_invoice_templates_customer
  ON invoice_templates(customer_id);

-- ── 2. Template run history ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS invoice_template_runs (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  template_id   INTEGER NOT NULL REFERENCES invoice_templates(id) ON DELETE CASCADE,
  invoice_id    INTEGER REFERENCES invoices(id),
  run_at        TEXT    NOT NULL DEFAULT (datetime('now')),
  succeeded     INTEGER NOT NULL DEFAULT 1,  -- 1 = ok, 0 = error
  error_message TEXT
);

CREATE INDEX IF NOT EXISTS idx_invoice_template_runs_template
  ON invoice_template_runs(template_id);

-- ── 3. Credit notes ──────────────────────────────────────────────────────────
-- Separate table (not invoice status) so open/applied/void states are explicit
-- and the audit trail is clean.

CREATE TABLE IF NOT EXISTS credit_notes (
  id                      INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id             INTEGER NOT NULL REFERENCES customers(id),
  original_invoice_id     INTEGER REFERENCES invoices(id),
  amount_cents            INTEGER NOT NULL CHECK(amount_cents > 0),
  reason                  TEXT    CHECK(reason IS NULL OR length(reason) <= 2000),
  status                  TEXT    NOT NULL DEFAULT 'open'
                                  CHECK(status IN ('open','applied','voided')),
  applied_to_invoice_id   INTEGER REFERENCES invoices(id),
  applied_at              TEXT,
  voided_at               TEXT,
  created_by_user_id      INTEGER NOT NULL REFERENCES users(id),
  created_at              TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_credit_notes_customer
  ON credit_notes(customer_id);

CREATE INDEX IF NOT EXISTS idx_credit_notes_status
  ON credit_notes(status);

CREATE INDEX IF NOT EXISTS idx_credit_notes_original_invoice
  ON credit_notes(original_invoice_id);
