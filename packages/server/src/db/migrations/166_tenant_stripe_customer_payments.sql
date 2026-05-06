-- ============================================================================
-- Migration 166 — tenant-owned Stripe customer payments
-- ============================================================================
--
-- Platform subscription billing continues to use the master DB + env
-- STRIPE_SECRET_KEY. These settings live in each tenant DB and belong to the
-- repair shop's own Stripe account.
-- ============================================================================

INSERT OR IGNORE INTO store_config (key, value) VALUES
  ('billing_pay_link_enabled', '0'),
  ('stripe_secret_key', ''),
  ('stripe_publishable_key', ''),
  ('stripe_webhook_secret', '');

ALTER TABLE payment_links ADD COLUMN processor_checkout_id TEXT;
ALTER TABLE payment_links ADD COLUMN processor_payment_intent_id TEXT;
ALTER TABLE payment_links ADD COLUMN processor_checkout_url TEXT;
ALTER TABLE payment_links ADD COLUMN processor_status TEXT;
ALTER TABLE payment_links ADD COLUMN processor_response TEXT;

CREATE INDEX IF NOT EXISTS idx_payment_links_provider_checkout
  ON payment_links(provider, processor_checkout_id);

CREATE INDEX IF NOT EXISTS idx_payment_links_provider_intent
  ON payment_links(provider, processor_payment_intent_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_stripe_intent_unique
  ON payments(processor_transaction_id)
  WHERE processor = 'stripe' AND processor_transaction_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS tenant_stripe_webhook_events (
  stripe_event_id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,
  payment_link_id INTEGER,
  payment_intent_id TEXT,
  status TEXT NOT NULL DEFAULT 'processing'
    CHECK(status IN ('processing', 'processed', 'ignored', 'failed')),
  error TEXT,
  processed_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_tenant_stripe_webhook_events_status
  ON tenant_stripe_webhook_events(status);

CREATE INDEX IF NOT EXISTS idx_tenant_stripe_webhook_events_intent
  ON tenant_stripe_webhook_events(payment_intent_id);
