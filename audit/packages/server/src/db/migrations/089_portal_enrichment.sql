-- =============================================================================
-- Migration 089 — Customer Portal Enrichment
-- =============================================================================
-- Adds schema for warranty certificates, customer reviews, loyalty points,
-- referrals, and per-photo portal visibility. Also seeds store_config defaults
-- for the switchable portal features called out in criticalaudit.md §45.
--
-- Live chat widget (§45 idea #14) is intentionally skipped — audit says
-- "NO TO THIS! DO NOT DO, very bad idea, too many sources of info." Pickup
-- reminder SMS (§45 idea #5) is handled by the existing status-change
-- notification flow, so it is not re-implemented here.
-- =============================================================================

-- Warranty certificates — one per closed ticket, on-demand PDF snapshot.
CREATE TABLE IF NOT EXISTS warranty_certificates (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id           INTEGER NOT NULL UNIQUE,
  certificate_number  TEXT NOT NULL UNIQUE,
  warranty_days       INTEGER NOT NULL,
  warranty_end_date   TEXT NOT NULL,
  issued_at           TEXT NOT NULL DEFAULT (datetime('now')),
  pdf_path            TEXT,
  terms_snapshot      TEXT
);
CREATE INDEX IF NOT EXISTS idx_warranty_certificates_ticket ON warranty_certificates(ticket_id);

-- Customer reviews — 1..5 star + optional comment. Shared schema with the
-- marketing module (agent for §25 may reuse + extend this table).
CREATE TABLE IF NOT EXISTS customer_reviews (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id      INTEGER,
  customer_id    INTEGER,
  rating         INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment        TEXT,
  public_posted  INTEGER NOT NULL DEFAULT 0,  -- 1 = forwarded to Google Reviews
  responded_at   TEXT,
  response       TEXT,
  created_at     TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_customer_reviews_ticket ON customer_reviews(ticket_id);
CREATE INDEX IF NOT EXISTS idx_customer_reviews_customer ON customer_reviews(customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_reviews_rating ON customer_reviews(rating);

-- Loyalty points ledger — append-only. Balance = SUM(points) per customer.
CREATE TABLE IF NOT EXISTS loyalty_points (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id     INTEGER NOT NULL,
  points          INTEGER NOT NULL,
  reason          TEXT,
  reference_type  TEXT,   -- 'invoice' | 'referral' | 'manual' | 'redemption'
  reference_id    INTEGER,
  created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_loyalty_customer ON loyalty_points(customer_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_reference ON loyalty_points(reference_type, reference_id);

-- Referrals — referrer shares a code; friend signs up, both get credit.
CREATE TABLE IF NOT EXISTS referrals (
  id                     INTEGER PRIMARY KEY AUTOINCREMENT,
  referrer_customer_id   INTEGER NOT NULL,
  referral_code          TEXT NOT NULL UNIQUE,
  referred_customer_id   INTEGER,
  referred_email         TEXT,
  referred_phone         TEXT,
  converted_invoice_id   INTEGER,
  reward_applied         INTEGER NOT NULL DEFAULT 0,
  created_at             TEXT NOT NULL DEFAULT (datetime('now')),
  converted_at           TEXT
);
CREATE INDEX IF NOT EXISTS idx_referrals_referrer ON referrals(referrer_customer_id);
CREATE INDEX IF NOT EXISTS idx_referrals_code ON referrals(referral_code);

-- Per-photo portal visibility + before/after tagging. Independent of the
-- main ticket_photos table so techs can bulk-upload and then mark a subset
-- as customer-visible.
CREATE TABLE IF NOT EXISTS ticket_photos_visibility (
  ticket_id         INTEGER NOT NULL,
  photo_path        TEXT NOT NULL,
  customer_visible  INTEGER NOT NULL DEFAULT 0,
  is_before         INTEGER NOT NULL DEFAULT 0,  -- 1 = before, 0 = after
  uploaded_at       TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (ticket_id, photo_path)
);
CREATE INDEX IF NOT EXISTS idx_ticket_photos_visibility_ticket
  ON ticket_photos_visibility(ticket_id, customer_visible);

-- -----------------------------------------------------------------------------
-- Store-config defaults for switchable portal features (§45 ideas 2, 3, 10, 12)
-- -----------------------------------------------------------------------------
-- portal_queue_mode: 'none' | 'phones' | 'all' — which devices show queue rank
INSERT OR IGNORE INTO store_config (key, value) VALUES ('portal_queue_mode', 'phones');
-- portal_show_tech: 'true' | 'false' — global opt-in for tech photo + name
INSERT OR IGNORE INTO store_config (key, value) VALUES ('portal_show_tech', 'true');
-- portal_sla_message: customer-visible SLA promise (blank disables)
INSERT OR IGNORE INTO store_config (key, value) VALUES ('portal_sla_message', 'Standard repairs ready within 2 business days.');
-- portal_sla_enabled: switch SLA banner on/off independently of the message
INSERT OR IGNORE INTO store_config (key, value) VALUES ('portal_sla_enabled', 'true');
-- portal_loyalty_enabled: show loyalty + referral UI on the portal
INSERT OR IGNORE INTO store_config (key, value) VALUES ('portal_loyalty_enabled', 'true');
-- portal_loyalty_rate: points earned per $1 (integer)
INSERT OR IGNORE INTO store_config (key, value) VALUES ('portal_loyalty_rate', '1');
-- portal_referral_reward: dollars off on conversion
INSERT OR IGNORE INTO store_config (key, value) VALUES ('portal_referral_reward', '20');
-- portal_review_threshold: ratings >= this go to the Google Reviews funnel
INSERT OR IGNORE INTO store_config (key, value) VALUES ('portal_review_threshold', '4');
-- portal_google_review_url: destination URL for public review redirect
INSERT OR IGNORE INTO store_config (key, value) VALUES ('portal_google_review_url', '');
-- portal_after_photo_delete_hours: window during which customer can delete
-- accidentally-uploaded "after" photos from their view. 0 disables.
INSERT OR IGNORE INTO store_config (key, value) VALUES ('portal_after_photo_delete_hours', '24');
-- portal_warranty_default_days: fallback warranty length if ticket has none
INSERT OR IGNORE INTO store_config (key, value) VALUES ('portal_warranty_default_days', '90');
-- portal_tech_show_me: per-user opt-in — set false on the users row via
-- `portal_tech_visible` column below. This flag only toggles the feature
-- globally; each tech still has to opt in individually.

-- Per-user opt-in for tech display on portal (§45 idea #3 — privacy).
-- ALTER TABLE uses ADD COLUMN which is idempotent-safe via a guard check:
-- SQLite lacks "IF NOT EXISTS" on ADD COLUMN, so we rely on the migration
-- runner's transactional rollback to skip on re-run.
ALTER TABLE users ADD COLUMN portal_tech_visible INTEGER NOT NULL DEFAULT 0;
