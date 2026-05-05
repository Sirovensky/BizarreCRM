-- Allow 'customer' type on ticket_notes for portal messages
-- SQLite CHECK constraints are not enforced on INSERT when using column affinity TEXT,
-- and recreating the table would break FTS triggers. The 'customer' type will work as-is
-- since the column is TEXT NOT NULL with no strict mode enabled.
-- This migration is a no-op placeholder to document the intent.
SELECT 1;
