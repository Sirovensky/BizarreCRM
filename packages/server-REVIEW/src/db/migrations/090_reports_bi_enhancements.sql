-- ============================================================================
-- 090 — Reports + Dashboard Business Intelligence enhancements (audit 47)
-- ============================================================================
--
-- Backing tables for the BI enrichment layer on top of the Wave 1 reports
-- routes. All three tables are additive — they only need to exist for the
-- new /reports/* endpoints introduced in this migration's companion PR.
--
-- 1. nps_responses           : "how likely are you to recommend us" (0-10)
--                              from post-pickup SMS / portal / email flow.
-- 2. scheduled_email_reports : owner-configured "mail me last week's summary
--                              every Monday 8am" entries. The Monday cron in
--                              reportEmailer.ts reads this.
-- 3. report_snapshots        : optional cache of expensive KPI computations
--                              keyed by (type, date). Lets the weekly email
--                              and the partner PDF re-use the same payload.
--
-- Also inserts the two switchable profit-hero thresholds into store_config.
-- Defaults: green >= 50%, amber >= 30%, red < 30% gross margin.
-- Owners flip these in Settings or via PATCH /reports/profit-hero/thresholds.
-- ----------------------------------------------------------------------------

-- ─── 1. NPS responses ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS nps_responses (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id  INTEGER NOT NULL,
  ticket_id    INTEGER,
  score        INTEGER NOT NULL CHECK (score BETWEEN 0 AND 10),
  comment      TEXT,
  channel      TEXT,                                            -- 'portal' | 'sms' | 'email'
  responded_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_nps_date        ON nps_responses(responded_at);
CREATE INDEX IF NOT EXISTS idx_nps_customer    ON nps_responses(customer_id);
CREATE INDEX IF NOT EXISTS idx_nps_ticket      ON nps_responses(ticket_id);

-- ─── 2. Scheduled email reports ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS scheduled_email_reports (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  name            TEXT NOT NULL,
  recipient_email TEXT NOT NULL,
  report_type     TEXT NOT NULL,                                -- 'weekly_summary' | 'monthly_tax' | 'partner_pdf'
  cron_schedule   TEXT NOT NULL,                                -- '0 8 * * 1' = Monday 8am local
  last_sent_at    TEXT,
  next_send_at    TEXT,
  is_active       INTEGER NOT NULL DEFAULT 1,
  config_json     TEXT,
  created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_sched_active ON scheduled_email_reports(is_active, next_send_at);

-- ─── 3. Report snapshots ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS report_snapshots (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  report_type   TEXT NOT NULL,
  snapshot_date TEXT NOT NULL,
  payload_json  TEXT NOT NULL,
  created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_snapshots_type_date ON report_snapshots(report_type, snapshot_date);

-- ─── 4. Profit-hero threshold defaults (switchable) ───────────────────────
-- Stored as store_config so the same Settings editor that handles the rest
-- of the config can toggle them. Both are INTEGER-string percentages.
INSERT OR IGNORE INTO store_config (key, value) VALUES ('profit_threshold_green', '50');
INSERT OR IGNORE INTO store_config (key, value) VALUES ('profit_threshold_amber', '30');
