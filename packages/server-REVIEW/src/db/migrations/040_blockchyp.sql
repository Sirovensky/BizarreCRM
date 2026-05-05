-- BlockChyp payment terminal integration
-- Adds signature storage on tickets and processor details on payments

-- Check-in signature captured via BlockChyp terminal
ALTER TABLE tickets ADD COLUMN signature_file TEXT;

-- Payment processor details
ALTER TABLE payments ADD COLUMN processor_transaction_id TEXT;
ALTER TABLE payments ADD COLUMN processor_response TEXT;
ALTER TABLE payments ADD COLUMN signature_file TEXT;
