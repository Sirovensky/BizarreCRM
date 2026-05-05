-- ============================================================================
-- Migration 096 — Team Management (criticalaudit.md §53)
-- ============================================================================
--
-- Purely additive. Adds the schema that powers the team-management enrichment
-- layer: shifts, time-off, my-queue (reads existing tickets), ticket handoffs,
-- @mentions, internal chat, payroll period locks, performance reviews,
-- team goals, custom roles + permission matrix, and an empty knowledge base.
--
-- DOES NOT touch users, employees, tickets, commissions, or clock_entries.
-- Knowledge-base table is created empty — audit forbids seeding any SOPs.
-- ============================================================================

-- ── 1. Shift schedules ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS shift_schedules (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  start_at TEXT NOT NULL,
  end_at TEXT NOT NULL,
  role TEXT,
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled','confirmed','swapped','missed','completed')),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  created_by_user_id INTEGER
);
CREATE INDEX IF NOT EXISTS idx_shifts_user_date
  ON shift_schedules(user_id, start_at);
CREATE INDEX IF NOT EXISTS idx_shifts_start
  ON shift_schedules(start_at);

-- ── 2. Time-off requests ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS time_off_requests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','denied','cancelled')),
  requested_at TEXT NOT NULL DEFAULT (datetime('now')),
  approved_by_user_id INTEGER,
  approved_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_time_off_user
  ON time_off_requests(user_id, status);

-- ── 3. Ticket handoffs ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ticket_handoffs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id INTEGER NOT NULL,
  from_user_id INTEGER NOT NULL,
  to_user_id INTEGER NOT NULL,
  reason TEXT NOT NULL,
  context TEXT,
  handed_off_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_handoffs_ticket
  ON ticket_handoffs(ticket_id, handed_off_at);

-- ── 4. @mentions ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS team_mentions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  mentioned_user_id INTEGER NOT NULL,
  mentioned_by_user_id INTEGER NOT NULL,
  context_type TEXT NOT NULL
    CHECK (context_type IN ('ticket_note','chat','invoice_note','customer_note')),
  context_id INTEGER NOT NULL,
  message_snippet TEXT,
  read_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_mentions_user_unread
  ON team_mentions(mentioned_user_id, read_at);

-- ── 5. Internal chat channels + messages ────────────────────────────────────
CREATE TABLE IF NOT EXISTS team_chat_channels (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('general','ticket','direct')),
  ticket_id INTEGER,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_chat_channels_kind
  ON team_chat_channels(kind);
CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_channels_ticket
  ON team_chat_channels(ticket_id) WHERE ticket_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS team_chat_messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_chat_msgs_channel
  ON team_chat_messages(channel_id, created_at);

-- Seed a single "general" channel so the page is non-empty on first visit.
-- This is the ONLY chat seed; ticket channels are created on-demand. Idempotent
-- via the SELECT-WHERE-NOT-EXISTS pattern (no UNIQUE constraint on name/kind).
INSERT INTO team_chat_channels (name, kind)
SELECT 'general', 'general'
WHERE NOT EXISTS (
  SELECT 1 FROM team_chat_channels WHERE kind = 'general'
);

-- ── 6. Payroll periods (lock for commission immutability) ───────────────────
CREATE TABLE IF NOT EXISTS payroll_periods (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  locked_at TEXT,
  locked_by_user_id INTEGER,
  notes TEXT
);
CREATE INDEX IF NOT EXISTS idx_payroll_periods_dates
  ON payroll_periods(start_date, end_date);

-- ── 7. Performance reviews ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS performance_reviews (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  reviewer_user_id INTEGER NOT NULL,
  period_start TEXT,
  period_end TEXT,
  notes TEXT NOT NULL,
  rating INTEGER CHECK (rating BETWEEN 1 AND 5),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_reviews_user
  ON performance_reviews(user_id, created_at);

-- ── 8. Goals + targets per tech ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS team_goals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  metric TEXT NOT NULL,
  target_value REAL NOT NULL,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_goals_user_period
  ON team_goals(user_id, period_start, period_end);

-- ── 9. Custom roles + permission matrix ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS custom_roles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS role_permissions (
  role_id INTEGER NOT NULL,
  permission_key TEXT NOT NULL,
  allowed INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (role_id, permission_key)
);

CREATE TABLE IF NOT EXISTS user_custom_roles (
  user_id INTEGER PRIMARY KEY,
  role_id INTEGER NOT NULL
);

-- Seed the 4 default roles to mirror the existing hardcoded enum.
-- (admin/manager/technician/cashier). Permissions are seeded in the route
-- layer the first time /api/v1/roles GETs them so we don't pin a stale list
-- here at migration time.
INSERT OR IGNORE INTO custom_roles (name, description) VALUES
  ('admin',      'Full administrative access'),
  ('manager',    'Manage staff, schedules, and reports'),
  ('technician', 'Repair tickets, parts, and bench work'),
  ('cashier',    'Point of sale, customers, and basic tickets');

-- ── 10. Knowledge base (empty per audit instructions) ───────────────────────
CREATE TABLE IF NOT EXISTS knowledge_base_articles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  tags TEXT,
  created_by_user_id INTEGER,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_kb_title
  ON knowledge_base_articles(title);
