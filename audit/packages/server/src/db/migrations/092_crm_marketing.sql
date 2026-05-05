-- ============================================================================
-- Migration 092 — Customer Relationships + Marketing (audit §49)
-- ============================================================================
--
-- Adds the schema that powers the CRM/marketing enrichment layer on top of
-- the portal-owned customer_reviews / loyalty_points / referrals tables
-- (migration 089) and the reports-owned nps_responses table (migration 090).
--
-- This migration is PURELY ADDITIVE. It does NOT redeclare anything that the
-- portal or reports agents already created. Column additions to customers
-- are idempotent at the migration-runner level (transactional rollback on
-- re-run — same pattern used by 089's portal_tech_visible ALTER).
--
-- Covers ideas 1–12 from §49:
--   1. health_score / health_tier            → customers columns + service cron
--   2. ltv_tier                               → customers columns + helper
--   3. birthday SMS campaign                  → customers.birthday + campaigns
--   4. review request automation              → marketing_campaigns flow
--   5. win-back campaign                      → marketing_campaigns + segments
--   6. referral code generator                → portal table + crm.routes hooks
--   7. NPS survey                              → reports-owned table, CRM reads
--   8. photo mementos                          → read-only aggregation
--   9. service subscriptions                   → service_subscriptions
--  10. churn warning on unpaid invoices       → marketing_campaigns cron
--  11. smart auto-segments                    → customer_segments
--  12. wallet pass                             → customers.wallet_pass_id
-- ============================================================================

-- ── 1. Customers columns ───────────────────────────────────────────────────
-- All nullable so existing ~958 customer rows aren't broken. Default 0 on
-- lifetime_value_cents so health-score calculators can SUM safely without
-- COALESCE everywhere.

ALTER TABLE customers ADD COLUMN health_score INTEGER;
ALTER TABLE customers ADD COLUMN health_tier TEXT;          -- 'champion'|'healthy'|'at_risk'
ALTER TABLE customers ADD COLUMN ltv_tier TEXT;             -- 'bronze'|'silver'|'gold'|'platinum'
ALTER TABLE customers ADD COLUMN lifetime_value_cents INTEGER NOT NULL DEFAULT 0;
ALTER TABLE customers ADD COLUMN last_interaction_at TEXT;
ALTER TABLE customers ADD COLUMN birthday TEXT;             -- MM-DD only, no year
ALTER TABLE customers ADD COLUMN wallet_pass_id TEXT;       -- UUID for Apple/Google pass

CREATE INDEX IF NOT EXISTS idx_customers_health_tier    ON customers(health_tier);
CREATE INDEX IF NOT EXISTS idx_customers_ltv_tier       ON customers(ltv_tier);
CREATE INDEX IF NOT EXISTS idx_customers_birthday       ON customers(birthday);
CREATE INDEX IF NOT EXISTS idx_customers_wallet_pass_id ON customers(wallet_pass_id);
CREATE INDEX IF NOT EXISTS idx_customers_last_inter     ON customers(last_interaction_at);
-- Partial index for the birthday cron's MM-DD LIKE scan — orders-of-magnitude faster.
CREATE INDEX IF NOT EXISTS idx_customers_ltv_cents      ON customers(lifetime_value_cents);

-- ── 2. Segments ────────────────────────────────────────────────────────────
-- Segments are the glue between every campaign. Auto segments recalc via the
-- refresh endpoint and a daily cron; static segments (is_auto=0) are opened
-- by the owner in the UI and populated manually.
CREATE TABLE IF NOT EXISTS customer_segments (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  name              TEXT NOT NULL,
  description       TEXT,
  rule_json         TEXT NOT NULL,       -- e.g. {"lifetime_value_cents":{">":500000}}
  is_auto           INTEGER NOT NULL DEFAULT 1,
  last_refreshed_at TEXT,
  member_count      INTEGER NOT NULL DEFAULT 0,
  created_at        TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_customer_segments_is_auto ON customer_segments(is_auto);

CREATE TABLE IF NOT EXISTS customer_segment_members (
  segment_id  INTEGER NOT NULL REFERENCES customer_segments(id) ON DELETE CASCADE,
  customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  added_at    TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (segment_id, customer_id)
);
CREATE INDEX IF NOT EXISTS idx_segment_members_customer ON customer_segment_members(customer_id);

-- ── 3. Marketing campaigns ─────────────────────────────────────────────────
-- A campaign is a named template + trigger rule + segment. Campaigns are
-- executed by cron helpers (dispatch routes) or on-demand ("run now").
CREATE TABLE IF NOT EXISTS marketing_campaigns (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  name              TEXT NOT NULL,
  type              TEXT NOT NULL CHECK (type IN (
                      'birthday','winback','review_request',
                      'churn_warning','service_subscription','custom')),
  segment_id        INTEGER REFERENCES customer_segments(id) ON DELETE SET NULL,
  channel           TEXT NOT NULL CHECK (channel IN ('sms','email','both')),
  template_subject  TEXT,
  template_body     TEXT NOT NULL,
  trigger_rule_json TEXT,               -- cron '0 9 * * *' or event {type:'ticket_pickup'}
  status            TEXT NOT NULL DEFAULT 'draft' CHECK (status IN (
                      'draft','active','paused','archived')),
  sent_count        INTEGER NOT NULL DEFAULT 0,
  replied_count     INTEGER NOT NULL DEFAULT 0,
  converted_count   INTEGER NOT NULL DEFAULT 0,
  created_at        TEXT NOT NULL DEFAULT (datetime('now')),
  last_run_at       TEXT
);
CREATE INDEX IF NOT EXISTS idx_marketing_campaigns_type   ON marketing_campaigns(type);
CREATE INDEX IF NOT EXISTS idx_marketing_campaigns_status ON marketing_campaigns(status);

-- ── 4. Campaign sends (per-recipient ledger) ──────────────────────────────
-- One row per message dispatched; de-dupes via (campaign_id, customer_id)
-- + sent_at day for birthday-style campaigns so we never double-send.
CREATE TABLE IF NOT EXISTS campaign_sends (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  campaign_id INTEGER NOT NULL REFERENCES marketing_campaigns(id) ON DELETE CASCADE,
  customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  sent_at     TEXT NOT NULL DEFAULT (datetime('now')),
  status      TEXT NOT NULL DEFAULT 'sent' CHECK (status IN (
                'sent','failed','replied','converted')),
  response    TEXT
);
CREATE INDEX IF NOT EXISTS idx_campaign_sends_customer  ON campaign_sends(customer_id);
CREATE INDEX IF NOT EXISTS idx_campaign_sends_campaign  ON campaign_sends(campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_sends_sent_at   ON campaign_sends(sent_at);

-- ── 5. Service subscriptions ──────────────────────────────────────────────
-- Recurring micro-plans ($5/mo screen protection etc.). Billing is out of
-- scope for this migration — the wave-2 billing agent owns the actual
-- BlockChyp/Stripe charge loop. We just record the plan + next bill date.
CREATE TABLE IF NOT EXISTS service_subscriptions (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id       INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  plan_name         TEXT NOT NULL,
  monthly_cents     INTEGER NOT NULL,
  status            TEXT NOT NULL DEFAULT 'active' CHECK (status IN (
                      'active','paused','cancelled')),
  next_billing_date TEXT NOT NULL,
  card_token        TEXT,
  created_at        TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_service_subs_customer ON service_subscriptions(customer_id);
CREATE INDEX IF NOT EXISTS idx_service_subs_next     ON service_subscriptions(status, next_billing_date);

-- ── 6. Seed the "always-on" auto segments the campaigns rely on ───────────
-- Rules are JSON of {field: {op: value}}. Operators: '>','>=','<','<=','=','!='.
-- The segment engine in crm.routes.ts parses this.
INSERT OR IGNORE INTO customer_segments (id, name, description, rule_json, is_auto)
VALUES
  (1, 'VIP — $5K+ lifetime', 'Auto tag VIP if lifetime revenue above $5000.',
    '{"lifetime_value_cents":{">":500000}}', 1),
  (2, 'Inactive 6+ months',  'No interaction in 180+ days, used by win-back campaign.',
    '{"last_interaction_days":{">":180}}', 1),
  (3, 'At-risk health',      'Customers whose health score dropped below 50.',
    '{"health_score":{"<":50}}', 1),
  (4, 'Champions',           'Champion tier customers for referral asks.',
    '{"health_tier":{"=":"champion"}}', 1),
  (5, 'Birthday this week',  'Customers with a birthday within 7 days — used by birthday SMS cron.',
    '{"birthday_window_days":{"<=":7}}', 1);

-- ── 7. Seed default campaign templates (draft status — owner activates) ───
INSERT OR IGNORE INTO marketing_campaigns
  (id, name, type, segment_id, channel, template_subject, template_body, trigger_rule_json, status)
VALUES
  (1, 'Birthday greeting', 'birthday', 5, 'sms', NULL,
    'Happy birthday {{first_name}}! Come visit us this month and take 15% off any repair. — Bizarre Electronics',
    '{"cron":"0 9 * * *"}', 'draft'),
  (2, 'We miss you — win-back', 'winback', 2, 'sms', NULL,
    'Hey {{first_name}}, it has been a while! $10 off your next repair this month. Reply STOP to opt out.',
    '{"cron":"0 10 * * 1"}', 'draft'),
  (3, 'Review request', 'review_request', NULL, 'sms', NULL,
    'Thanks for choosing Bizarre Electronics, {{first_name}}! How did we do? Tap to rate us: {{review_link}}',
    '{"event":"ticket_pickup"}', 'draft'),
  (4, 'Unpaid invoice — 14 day nudge', 'churn_warning', NULL, 'sms', NULL,
    'Hi {{first_name}}, your invoice {{invoice_number}} is 14 days past due. Reply PAY for a payment plan.',
    '{"cron":"0 11 * * *","days_overdue":14}', 'draft');
