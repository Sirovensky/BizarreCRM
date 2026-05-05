-- ============================================================================
-- 088 — Bench timer, QC sign-off, and parts defect reporter (audit 44.6/10/14)
-- ============================================================================
--
-- Audit 44.6  : "start work -> live counter in sidebar, pause for breaks,
--                stop logs duration + labor cost. Aggregates to payroll.
--                should be switchable - not all shops need this"
-- Audit 44.10 : "QC sign-off modal: screen clean / touch responsive / colors
--                accurate / tested with customer. Tech signs, photo attached."
-- Audit 44.14 : "Parts defect reporter: one-click 'Report defect' increments
--                defect_count. 'LCD X has 4 defects in 30 days' alert."
--
-- All three domains live in one migration because they're a single feature
-- set: "technician accountability + quality feedback loop". Splitting them
-- across three files would only make it harder to roll back one experiment
-- without breaking the other two.
--
-- SWITCHABILITY:
--   bench_timer_enabled  : global on/off. When OFF, the timer UI is hidden
--                          and /bench/timer/* returns {success, data:null}
--                          instead of 404, so the frontend degrades gracefully.
--   qc_required          : if TRUE, /tickets/:id PATCH status='complete' is
--                          blocked server-side until a qc_sign_offs row exists.
--   defect_alert_threshold_30d : when a part crosses this count in the last
--                                30 days, a notification fires to procurement.
-- ----------------------------------------------------------------------------

-- ─── Bench timer ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bench_timers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id INTEGER NOT NULL,
  ticket_device_id INTEGER,                       -- NULL = whole-ticket timer
  user_id INTEGER NOT NULL,
  started_at TEXT NOT NULL DEFAULT (datetime('now')),
  ended_at TEXT,                                  -- NULL while active or paused
  pause_log_json TEXT,                            -- JSON [{pause_at, resume_at}]
  total_seconds INTEGER,                          -- filled on stop
  labor_rate_cents INTEGER,                       -- cents/hour snapshot
  labor_cost_cents INTEGER,                       -- (total_seconds/3600)*rate
  notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_bench_timers_ticket ON bench_timers(ticket_id);
CREATE INDEX IF NOT EXISTS idx_bench_timers_user_active
  ON bench_timers(user_id) WHERE ended_at IS NULL;

-- ─── QC checklist catalogue ────────────────────────────────────────────────
-- Admin-editable list of items a tech must tick off before a ticket can be
-- marked complete. device_category scopes the list — phone repairs get
-- different items than TV repairs.
CREATE TABLE IF NOT EXISTS qc_checklist_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  device_category TEXT                            -- NULL = applies to all
);

-- Seed a sensible default list so a brand-new shop has something to show.
INSERT OR IGNORE INTO qc_checklist_items (name, sort_order, device_category) VALUES
  ('Screen clean and scratch-free', 10, NULL),
  ('Touch responsive across entire display', 20, NULL),
  ('Colors and brightness look correct', 30, NULL),
  ('Buttons (power / volume / home) work', 40, NULL),
  ('Cameras (front + rear) focus and shoot', 50, NULL),
  ('Speakers and microphone tested', 60, NULL),
  ('Charging port stable, cable seats', 70, NULL),
  ('Wi-Fi / cellular connection verified', 80, NULL),
  ('Tested WITH customer (or customer video)', 90, NULL);

-- ─── QC sign-offs ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS qc_sign_offs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id INTEGER NOT NULL,
  ticket_device_id INTEGER,
  tech_user_id INTEGER NOT NULL,
  checklist_results_json TEXT NOT NULL,           -- JSON [{item_id, passed}]
  tech_signature_path TEXT,                       -- PNG blob on disk
  working_photo_path TEXT,                        -- JPG of the working device
  signed_at TEXT NOT NULL DEFAULT (datetime('now')),
  notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_qc_sign_offs_ticket ON qc_sign_offs(ticket_id);

-- ─── Parts defect reporter ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS parts_defect_reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  inventory_item_id INTEGER NOT NULL,
  ticket_id INTEGER,                              -- NULL = caught before install
  reported_by_user_id INTEGER NOT NULL,
  defect_type TEXT,                               -- doa | intermittent | cosmetic | wrong_spec
  description TEXT,
  photo_path TEXT,
  reported_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_defect_reports_item
  ON parts_defect_reports(inventory_item_id, reported_at);

-- ─── Config flags ──────────────────────────────────────────────────────────
INSERT OR IGNORE INTO store_config (key, value) VALUES
  ('bench_timer_enabled', 'false'),
  ('bench_labor_rate_cents', '5000'),             -- $50/hr default
  ('qc_required', 'false'),
  ('defect_alert_threshold_30d', '4');
