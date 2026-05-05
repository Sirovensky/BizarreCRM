-- Membership tiers (per-tenant, editable)
CREATE TABLE IF NOT EXISTS membership_tiers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  slug TEXT NOT NULL,
  monthly_price REAL NOT NULL,
  discount_pct REAL NOT NULL DEFAULT 0,
  discount_applies_to TEXT NOT NULL DEFAULT 'labor',  -- 'labor', 'all', 'parts'
  benefits TEXT DEFAULT '[]',  -- JSON array of benefit strings
  color TEXT DEFAULT '#3b82f6',
  sort_order INTEGER NOT NULL DEFAULT 0,
  customer_group_id INTEGER REFERENCES customer_groups(id),
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Customer subscriptions
CREATE TABLE IF NOT EXISTS customer_subscriptions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  tier_id INTEGER NOT NULL REFERENCES membership_tiers(id),
  blockchyp_token TEXT,              -- Tokenized card for recurring charges
  blockchyp_customer_id TEXT,        -- BlockChyp customer record
  status TEXT NOT NULL DEFAULT 'active',  -- active, past_due, cancelled, paused
  current_period_start TEXT NOT NULL DEFAULT (datetime('now')),
  current_period_end TEXT NOT NULL,
  cancel_at_period_end INTEGER NOT NULL DEFAULT 0,
  pause_reason TEXT,
  last_charge_at TEXT,
  last_charge_amount REAL,
  failed_charge_count INTEGER NOT NULL DEFAULT 0,
  signature_file TEXT,               -- T&C signature captured via BlockChyp
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_cs_customer ON customer_subscriptions(customer_id);
CREATE INDEX IF NOT EXISTS idx_cs_status ON customer_subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_cs_period_end ON customer_subscriptions(current_period_end);

-- Subscription payment history
CREATE TABLE IF NOT EXISTS subscription_payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  subscription_id INTEGER NOT NULL REFERENCES customer_subscriptions(id),
  amount REAL NOT NULL,
  status TEXT NOT NULL DEFAULT 'success',  -- success, failed, refunded
  blockchyp_transaction_id TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Quick lookup on customer
ALTER TABLE customers ADD COLUMN active_subscription_id INTEGER REFERENCES customer_subscriptions(id);

-- Seed starter presets (editable per tenant)
INSERT OR IGNORE INTO membership_tiers (name, slug, monthly_price, discount_pct, discount_applies_to, benefits, color, sort_order)
VALUES
  ('Basic', 'basic', 15.00, 10, 'labor', '["10% off repair labor","5 hours lounge access","Priority scheduling"]', '#60a5fa', 1),
  ('Pro', 'pro', 25.00, 20, 'labor', '["20% off repair labor","15 hours lounge access","Priority scheduling","Free diagnostics"]', '#a78bfa', 2),
  ('VIP', 'vip', 30.00, 30, 'all', '["30% off all services","30% off events","30 hours lounge access","Priority scheduling","Free diagnostics","Extended warranty"]', '#f59e0b', 3);

-- Membership settings
INSERT OR IGNORE INTO store_config (key, value) VALUES ('membership_enabled', 'false');
INSERT OR IGNORE INTO store_config (key, value) VALUES ('membership_grace_period_days', '3');
INSERT OR IGNORE INTO store_config (key, value) VALUES ('membership_auto_renewal', 'true');
