-- Automation execution history / run log (audit section 24, AU6).
-- Every automation execution attempt (success OR failure) inserts a row here so
-- operators can trace which automations fired, what they targeted, and why they
-- failed. Referenced by services/automations.ts via logAutomationRun().
--
-- This table lives in each tenant DB because automations themselves are per-tenant.
CREATE TABLE IF NOT EXISTS automation_run_log (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  automation_id         INTEGER NOT NULL,
  automation_name       TEXT,
  trigger_event         TEXT NOT NULL,
  action_type           TEXT,
  target_entity_type    TEXT,                         -- 'ticket', 'customer', 'invoice', etc.
  target_entity_id      INTEGER,
  status                TEXT NOT NULL,                -- 'success', 'failure', 'skipped', 'loop_rejected'
  error_message         TEXT,
  depth                 INTEGER NOT NULL DEFAULT 0,   -- recursion depth for change_status loops
  created_at            TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Common lookup patterns: latest runs per automation, failures only, per-ticket history.
CREATE INDEX IF NOT EXISTS idx_automation_run_log_automation_id ON automation_run_log(automation_id);
CREATE INDEX IF NOT EXISTS idx_automation_run_log_created_at    ON automation_run_log(created_at);
CREATE INDEX IF NOT EXISTS idx_automation_run_log_status        ON automation_run_log(status);
CREATE INDEX IF NOT EXISTS idx_automation_run_log_entity        ON automation_run_log(target_entity_type, target_entity_id);
