-- ============================================================================
-- Migration 102 — Customer notes (CROSS9b)
-- ============================================================================
--
-- Adds a multi-row notes table keyed to a customer. The existing
-- `customers.comments` column remains the single-line "sticky note" edited
-- inline from the Edit Profile flow; this new table is an append-only
-- timeline of dated notes (who wrote it, when) that powers the Notes card
-- on Android CustomerDetail and future web parity.
--
-- Body capped at 5000 chars at the application layer to keep the card render
-- lightweight. No FK to users(id) column-level because some legacy notes
-- may be backfilled from imports without a resolvable author; we simply
-- leave author_user_id nullable.
-- ============================================================================

CREATE TABLE IF NOT EXISTS customer_notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL,
  author_user_id INTEGER,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_customer_notes_customer
  ON customer_notes(customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_notes_created
  ON customer_notes(customer_id, created_at DESC);
