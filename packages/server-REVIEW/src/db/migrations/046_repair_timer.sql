-- SW-D9: Repair timer auto-start/stop on status change
-- Track when the repair timer was started so we can calculate elapsed time
ALTER TABLE tickets ADD COLUMN repair_timer_started_at TEXT DEFAULT NULL;
ALTER TABLE tickets ADD COLUMN repair_timer_running INTEGER NOT NULL DEFAULT 0;
