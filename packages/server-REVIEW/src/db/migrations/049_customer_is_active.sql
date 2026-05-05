-- ============================================================================
-- Migration 049: Add is_active column to customers for archival feature
-- ============================================================================
ALTER TABLE customers ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1;

CREATE INDEX IF NOT EXISTS idx_customers_is_active ON customers(is_active);
