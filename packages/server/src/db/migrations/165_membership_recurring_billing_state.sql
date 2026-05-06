-- TS2 — recurring membership billing retry state.
--
-- The existing membership tables could store a period end and last charge, but
-- they had no durable retry schedule. These columns make the hourly renewal
-- worker restart-safe and give operators visibility into suspended renewals.

ALTER TABLE customer_subscriptions ADD COLUMN auto_renew INTEGER NOT NULL DEFAULT 1;
ALTER TABLE customer_subscriptions ADD COLUMN next_billing_attempt_at TEXT;
ALTER TABLE customer_subscriptions ADD COLUMN billing_retry_stage INTEGER NOT NULL DEFAULT 0;
ALTER TABLE customer_subscriptions ADD COLUMN last_charge_failed_at TEXT;
ALTER TABLE customer_subscriptions ADD COLUMN last_charge_error TEXT;
ALTER TABLE customer_subscriptions ADD COLUMN billing_suspended_at TEXT;
ALTER TABLE customer_subscriptions ADD COLUMN payment_provider TEXT NOT NULL DEFAULT 'blockchyp';

ALTER TABLE subscription_payments ADD COLUMN billing_run_id INTEGER REFERENCES membership_billing_runs(id);
ALTER TABLE subscription_payments ADD COLUMN payment_provider TEXT NOT NULL DEFAULT 'blockchyp';
ALTER TABLE subscription_payments ADD COLUMN processor_transaction_id TEXT;

CREATE INDEX IF NOT EXISTS idx_customer_subscriptions_billing_due
  ON customer_subscriptions(status, auto_renew, current_period_end, next_billing_attempt_at)
  WHERE status IN ('active', 'past_due') AND auto_renew = 1;

CREATE INDEX IF NOT EXISTS idx_subscription_payments_billing_run
  ON subscription_payments(billing_run_id);
