-- Add is_pinned flag to tickets for starring/pinning tickets to the top
ALTER TABLE tickets ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;

-- Index for efficient sorting pinned tickets first
CREATE INDEX IF NOT EXISTS idx_tickets_pinned ON tickets (is_pinned DESC, created_at DESC);
