-- WEB-UNWIRED-033 — Persist accepted BlockChyp invoice/refund signature terms.
--
-- BlockChyp payment/refund terminal terms are captured through the terminal
-- Terms & Conditions API. Store the exact accepted text and hash on the
-- financial row so later settings edits cannot rewrite the audit record.

ALTER TABLE payments ADD COLUMN accepted_terms_name TEXT;
ALTER TABLE payments ADD COLUMN accepted_terms_text TEXT;
ALTER TABLE payments ADD COLUMN accepted_terms_hash TEXT;
ALTER TABLE payments ADD COLUMN accepted_terms_accepted_at TEXT;

ALTER TABLE refunds ADD COLUMN processor TEXT;
ALTER TABLE refunds ADD COLUMN processor_transaction_id TEXT;
ALTER TABLE refunds ADD COLUMN processor_response TEXT;
ALTER TABLE refunds ADD COLUMN signature_file TEXT;
ALTER TABLE refunds ADD COLUMN signature_file_path TEXT;
ALTER TABLE refunds ADD COLUMN accepted_terms_name TEXT;
ALTER TABLE refunds ADD COLUMN accepted_terms_text TEXT;
ALTER TABLE refunds ADD COLUMN accepted_terms_hash TEXT;
ALTER TABLE refunds ADD COLUMN accepted_terms_accepted_at TEXT;

CREATE INDEX IF NOT EXISTS idx_payments_accepted_terms_hash
  ON payments(accepted_terms_hash);

CREATE INDEX IF NOT EXISTS idx_refunds_processor_transaction
  ON refunds(processor, processor_transaction_id);

CREATE INDEX IF NOT EXISTS idx_refunds_accepted_terms_hash
  ON refunds(accepted_terms_hash);
