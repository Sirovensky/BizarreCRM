-- Migration 191 — WEB-UIUX-634: parent-payment / refund-payment links so the
-- BlockChyp/Stripe refund approval path can pick the exact captured payment
-- being refunded instead of "the latest captured payment on the invoice"
-- (which silently mis-refunds split tenders or multiple card captures).
--
-- Both columns are nullable so legacy rows keep validating. New writes wire
-- them in over time; reports that need the link gracefully fall back to the
-- legacy lookup when NULL.
ALTER TABLE refunds ADD COLUMN original_payment_id INTEGER REFERENCES payments(id);
ALTER TABLE payments ADD COLUMN refund_of_payment_id INTEGER REFERENCES payments(id);

CREATE INDEX IF NOT EXISTS idx_refunds_original_payment
  ON refunds(original_payment_id) WHERE original_payment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payments_refund_of
  ON payments(refund_of_payment_id) WHERE refund_of_payment_id IS NOT NULL;
