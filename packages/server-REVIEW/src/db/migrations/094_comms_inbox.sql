-- ============================================================================
-- Migration 094 — Communications Team Inbox enrichment (audit §51)
-- ============================================================================
--
-- Adds the schema that powers the team-inbox enrichment layer on top of the
-- existing sms_messages / sms_templates / conversation_* tables. This
-- migration is PURELY ADDITIVE — no sms_messages columns are modified, so
-- every existing sms.routes.ts / portal.routes.ts / automations.routes.ts
-- query keeps working unchanged.
--
-- Covers ideas 1, 3, 4, 5, 6, 9, 11, 12 from §51:
--   1.  Shared team inbox with assignment  → conversation_assignments
--   2.  (UI-only hotkeys) — no table
--   3.  Bulk SMS to a segment              → bulk send uses sms_retry_queue
--   4.  SMS delivery retry UI              → sms_retry_queue
--   5.  Customer sentiment detection       → sms_sentiment_history
--   6.  Conversation auto-tagging          → conversation_tags
--   9.  Compliance archive toggle          → store_config key
--   11. Template analytics                 → sms_template_analytics
--   12. Auto-off-hours reply               → store_config keys
-- ============================================================================

-- ── 1. Conversation assignment (idea §51.1) ────────────────────────────────
-- Shared team inbox. Each conversation (keyed by normalized phone) can be
-- claimed by exactly one user. A nullable assigned_user_id means "unclaimed".
CREATE TABLE IF NOT EXISTS conversation_assignments (
  phone TEXT PRIMARY KEY,
  assigned_user_id INTEGER,
  assigned_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_conv_assignments_user
  ON conversation_assignments(assigned_user_id);

-- ── 2. Conversation tags (idea §51.6) ──────────────────────────────────────
-- Manual tags only for now. Auto-tagging moved to v2 (requires NLP).
CREATE TABLE IF NOT EXISTS conversation_tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone TEXT NOT NULL,
  tag TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(phone, tag)
);
CREATE INDEX IF NOT EXISTS idx_conv_tags_phone ON conversation_tags(phone);
CREATE INDEX IF NOT EXISTS idx_conv_tags_tag ON conversation_tags(tag);

-- ── 3. Per-user read receipts (idea §51.1) ─────────────────────────────────
-- sms_messages already has a conversation-level unread count; this adds
-- per-user tracking so "unread for Mike" differs from "unread for Sarah".
CREATE TABLE IF NOT EXISTS conversation_read_receipts (
  phone TEXT NOT NULL,
  user_id INTEGER NOT NULL,
  last_read_message_id INTEGER,
  last_read_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (phone, user_id)
);
CREATE INDEX IF NOT EXISTS idx_conv_read_user
  ON conversation_read_receipts(user_id);

-- ── 4. SMS delivery retry queue (idea §51.4) ───────────────────────────────
-- When sms_messages.status = 'failed' we enqueue a retry row. The UI surfaces
-- "Failed sends" with per-row "Retry" / "Cancel" buttons. Exponential backoff
-- tracked via retry_count + next_retry_at. No background worker yet — clicks
-- drive the retry.
CREATE TABLE IF NOT EXISTS sms_retry_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  original_message_id INTEGER,
  to_phone TEXT NOT NULL,
  body TEXT NOT NULL,
  retry_count INTEGER NOT NULL DEFAULT 0,
  next_retry_at TEXT NOT NULL,
  last_error TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','succeeded','failed','cancelled')),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_sms_retry_status ON sms_retry_queue(status);
CREATE INDEX IF NOT EXISTS idx_sms_retry_next ON sms_retry_queue(next_retry_at);

-- ── 5. Template analytics (idea §51.11) ────────────────────────────────────
-- Aggregate counter table — incremented by inbox.routes on every template send
-- and every inbound reply received within 24h of a template send. Row is
-- one-per-template (UNIQUE template_id). Use UPSERT pattern.
CREATE TABLE IF NOT EXISTS sms_template_analytics (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  template_id INTEGER NOT NULL,
  sent_count INTEGER NOT NULL DEFAULT 0,
  reply_count INTEGER NOT NULL DEFAULT 0,
  last_sent_at TEXT,
  UNIQUE(template_id)
);

-- ── 6. Sentiment history (idea §51.5) ──────────────────────────────────────
-- Each inbound message can have a sentiment classification attached. Score is
-- an integer in [0..100] — higher = more confident. Classifier is purely
-- keyword-based on the web client; this table stores the result the UI sent
-- back so reports can query historical sentiment trend per customer.
CREATE TABLE IF NOT EXISTS sms_sentiment_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  message_id INTEGER,
  phone TEXT NOT NULL,
  sentiment TEXT NOT NULL
    CHECK (sentiment IN ('angry','neutral','happy','urgent')),
  score INTEGER,
  detected_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_sms_sentiment_phone ON sms_sentiment_history(phone);
CREATE INDEX IF NOT EXISTS idx_sms_sentiment_kind ON sms_sentiment_history(sentiment);

-- ── 7. Store config defaults (ideas §51.9 & §51.12) ────────────────────────
-- Round-robin auto-assignment (default — alternative is 'manual').
-- Off-hours auto-reply toggle (default off). Message is editable.
-- Compliance archive retention (0 = no retention policy; 7 = 7-year archive).
INSERT OR IGNORE INTO store_config (key, value) VALUES
  ('inbox_auto_assignment', 'round_robin'),
  ('inbox_off_hours_autoreply_enabled', '0'),
  ('inbox_off_hours_autoreply_message', 'Thanks for your message. We will reply during business hours.'),
  ('inbox_compliance_archive_years', '0');
