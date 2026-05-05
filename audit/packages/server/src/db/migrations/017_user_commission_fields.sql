-- Add commission configuration fields to users
ALTER TABLE users ADD COLUMN commission_rate REAL NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN commission_type TEXT NOT NULL DEFAULT 'none';
-- commission_type: 'none' | 'percent_ticket' | 'percent_service' | 'flat_per_ticket'
