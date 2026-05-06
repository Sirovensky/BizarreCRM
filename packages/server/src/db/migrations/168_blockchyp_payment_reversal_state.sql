-- SEC-H40 / SEC-H41: processor-aware reversals for BlockChyp payments and deposits.
--
-- Adds lightweight pending markers so a local row is claimed before the server
-- calls the external processor. This prevents duplicate void/refund clicks from
-- dispatching two processor operations against the same local financial row.

ALTER TABLE payments ADD COLUMN void_pending_at TEXT;
ALTER TABLE payments ADD COLUMN voided_at TEXT;
ALTER TABLE payments ADD COLUMN voided_by_user_id INTEGER REFERENCES users(id);
ALTER TABLE payments ADD COLUMN void_error TEXT;
ALTER TABLE payments ADD COLUMN capture_pending_at TEXT;
ALTER TABLE payments ADD COLUMN captured_at TEXT;
ALTER TABLE payments ADD COLUMN captured_by_user_id INTEGER REFERENCES users(id);
ALTER TABLE payments ADD COLUMN capture_error TEXT;

CREATE INDEX IF NOT EXISTS idx_payments_void_pending
  ON payments(void_pending_at)
  WHERE void_pending_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_payments_capture_pending
  ON payments(capture_pending_at)
  WHERE capture_pending_at IS NOT NULL;

ALTER TABLE refunds ADD COLUMN processor_pending_at TEXT;
ALTER TABLE refunds ADD COLUMN processor_error TEXT;

CREATE INDEX IF NOT EXISTS idx_refunds_processor_pending
  ON refunds(processor_pending_at)
  WHERE processor_pending_at IS NOT NULL;

ALTER TABLE deposits ADD COLUMN payment_id INTEGER REFERENCES payments(id);
ALTER TABLE deposits ADD COLUMN applied_payment_id INTEGER REFERENCES payments(id);
ALTER TABLE deposits ADD COLUMN processor TEXT;
ALTER TABLE deposits ADD COLUMN processor_transaction_id TEXT;
ALTER TABLE deposits ADD COLUMN processor_refund_transaction_id TEXT;
ALTER TABLE deposits ADD COLUMN processor_response TEXT;
ALTER TABLE deposits ADD COLUMN refund_pending_at TEXT;
ALTER TABLE deposits ADD COLUMN refund_error TEXT;
ALTER TABLE deposits ADD COLUMN refunded_by_user_id INTEGER REFERENCES users(id);
ALTER TABLE deposits ADD COLUMN refund_signature_file TEXT;
ALTER TABLE deposits ADD COLUMN refund_signature_file_path TEXT;
ALTER TABLE deposits ADD COLUMN accepted_terms_name TEXT;
ALTER TABLE deposits ADD COLUMN accepted_terms_text TEXT;
ALTER TABLE deposits ADD COLUMN accepted_terms_hash TEXT;
ALTER TABLE deposits ADD COLUMN accepted_terms_accepted_at TEXT;

CREATE INDEX IF NOT EXISTS idx_deposits_payment_id
  ON deposits(payment_id);

CREATE INDEX IF NOT EXISTS idx_deposits_applied_payment_id
  ON deposits(applied_payment_id);

CREATE INDEX IF NOT EXISTS idx_deposits_processor_transaction
  ON deposits(processor, processor_transaction_id);

CREATE INDEX IF NOT EXISTS idx_deposits_refund_pending
  ON deposits(refund_pending_at)
  WHERE refund_pending_at IS NOT NULL;
