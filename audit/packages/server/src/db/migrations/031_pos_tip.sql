-- Add tip/gratuity field to POS transactions
ALTER TABLE pos_transactions ADD COLUMN tip REAL DEFAULT 0;
