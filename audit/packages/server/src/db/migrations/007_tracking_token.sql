-- Migration 007: Add tracking token to tickets for public lookup
-- ============================================================================

ALTER TABLE tickets ADD COLUMN tracking_token TEXT;

-- Index for fast token lookups
CREATE INDEX IF NOT EXISTS idx_tickets_tracking_token ON tickets(tracking_token);
