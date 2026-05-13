-- WEB-UIUX-1117: bulk-SMS dispatch becomes a tracked job so the request
-- returns immediately, the modal can poll for progress, and the operator
-- can hit Abort without killing the server.
CREATE TABLE IF NOT EXISTS bulk_sms_jobs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  segment            TEXT NOT NULL,
  template_id        INTEGER NOT NULL,
  template_name      TEXT,
  total              INTEGER NOT NULL DEFAULT 0,
  sent               INTEGER NOT NULL DEFAULT 0,
  failed             INTEGER NOT NULL DEFAULT 0,
  status             TEXT NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending', 'running', 'completed', 'aborted', 'failed')),
  abort_requested    INTEGER NOT NULL DEFAULT 0 CHECK (abort_requested IN (0, 1)),
  last_error         TEXT,
  created_by         INTEGER NOT NULL,
  created_at         TEXT NOT NULL DEFAULT (datetime('now')),
  started_at         TEXT,
  finished_at        TEXT
);

CREATE INDEX IF NOT EXISTS idx_bulk_sms_jobs_status ON bulk_sms_jobs(status);
CREATE INDEX IF NOT EXISTS idx_bulk_sms_jobs_created_at ON bulk_sms_jobs(created_at);
