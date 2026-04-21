-- ============================================================================
-- 115 — Onboarding Milestone Triggers (audit section 42 / Phase A1)
-- ============================================================================
--
-- Purpose:
--   Automatically stamps `onboarding_state.first_<kind>_at` the first time a
--   real customer / ticket / invoice / payment is created. "First time" is
--   enforced by the `WHERE first_<kind>_at IS NULL` guard so the timestamp is
--   written exactly once and never overwritten.
--
-- Sample-data exclusion rationale:
--   `loadSampleData()` inserts demo rows tagged with the string 'sample' so
--   shop owners can explore the UI before committing real data. Those demo
--   inserts must NOT set the milestone timestamps — otherwise "first customer"
--   fires on a synthetic Alex Demo row, the confetti toast fires immediately,
--   and the user never gets the real first-customer celebration after they type
--   in their actual first client.
--
--   Strategy per table:
--     customers  — `tags` column holds JSON.stringify(['sample']); check NOT LIKE '%sample%'.
--     tickets    — `labels` column holds JSON.stringify(['sample']); same check.
--     invoices   — no labels column; sample invoices have `order_id LIKE 'SAMPLE-%'`.
--     payments   — no tags column; exclude by checking the parent invoice's order_id
--                  via a correlated SELECT in the WHEN clause.
--
-- Style follows migration 086_onboarding_and_sample_data.sql.
-- ----------------------------------------------------------------------------

-- ── customers ────────────────────────────────────────────────────────────────
-- Excludes WALK-IN pseudo-customers (code = 'WALK-IN') which are system rows
-- created automatically on every POS anonymous sale — those should not count
-- as "first real customer". Also excludes sample-tagged rows.
CREATE TRIGGER IF NOT EXISTS trg_onboarding_first_customer
AFTER INSERT ON customers
WHEN (NEW.tags IS NULL OR NEW.tags NOT LIKE '%sample%')
  AND (NEW.code IS NULL OR NEW.code != 'WALK-IN')
BEGIN
  UPDATE onboarding_state
    SET first_customer_at = datetime('now'),
        updated_at        = datetime('now')
    WHERE id = 1 AND first_customer_at IS NULL;
END;

-- ── tickets ──────────────────────────────────────────────────────────────────
CREATE TRIGGER IF NOT EXISTS trg_onboarding_first_ticket
AFTER INSERT ON tickets
WHEN (NEW.labels IS NULL OR NEW.labels NOT LIKE '%sample%')
BEGIN
  UPDATE onboarding_state
    SET first_ticket_at = datetime('now'),
        updated_at      = datetime('now')
    WHERE id = 1 AND first_ticket_at IS NULL;
END;

-- ── invoices ─────────────────────────────────────────────────────────────────
-- Sample invoices use order_id LIKE 'SAMPLE-%' (e.g. SAMPLE-INV001).
CREATE TRIGGER IF NOT EXISTS trg_onboarding_first_invoice
AFTER INSERT ON invoices
WHEN (NEW.order_id IS NULL OR NEW.order_id NOT LIKE 'SAMPLE-%')
BEGIN
  UPDATE onboarding_state
    SET first_invoice_at = datetime('now'),
        updated_at       = datetime('now')
    WHERE id = 1 AND first_invoice_at IS NULL;
END;

-- ── payments ─────────────────────────────────────────────────────────────────
-- The payments table has no tag column. Detect sample payments by looking up
-- the parent invoice's order_id. A payment is "sample" if its invoice has an
-- order_id matching 'SAMPLE-%'.
CREATE TRIGGER IF NOT EXISTS trg_onboarding_first_payment
AFTER INSERT ON payments
WHEN (
  SELECT order_id FROM invoices WHERE id = NEW.invoice_id
) NOT LIKE 'SAMPLE-%'
BEGIN
  UPDATE onboarding_state
    SET first_payment_at = datetime('now'),
        updated_at       = datetime('now')
    WHERE id = 1 AND first_payment_at IS NULL;
END;
