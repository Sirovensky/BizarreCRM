-- SA7-1: Persist import-job progress so a crash mid-import can resume
-- from the last confirmed checkpoint instead of replaying the whole job.
--
-- Context:
--   Long-running import services (repairDeskImport, repairShoprImport,
--   myRepairAppImport, reimport-notes) walk the remote catalog with a
--   sleep-between-page/sleep-between-record loop. If the Node process
--   crashes (OOM, uncaught rejection, machine restart) the in-memory
--   cursor is lost and the only recovery path was "re-run from scratch".
--   That replays thousands of HTTP requests + wastes the remote API's
--   quota.
--
-- Fix: a per-job checkpoint row that is updated atomically with the
-- batch of data writes it represents. On restart the CLI `--resume`
-- flag reads the row, skips everything up to `last_processed_id`, and
-- continues. A fresh run (default or `--start-fresh`) deletes the row
-- and starts at offset 0.
--
--   job_id              string PK — stable key per job. Format:
--                          "<source>:<entity>:<tenant>" e.g.
--                          "repairdesk:tickets:default" or
--                          "reimport-notes:bizarre"
--   step                current offset inside the stream (processed count)
--   total               total records we expect to process (0 if unknown)
--   last_processed_id   cursor value — for page-based APIs this is the
--                         last page number processed; for per-record
--                         loops (reimport-notes, notes-and-history
--                         fetch) it is the source record id. Stored as
--                         TEXT to accept either.
--   status              pending | running | paused | completed | failed
--   last_error          optional error string for visibility
--   started_at          ISO timestamp of first claim
--   updated_at          ISO timestamp of the most recent checkpoint
--
-- Writes are always inside the same transaction as the data writes they
-- represent, so a crash between "wrote 50 rows" and "checkpointed 50 rows"
-- is impossible — either both land or neither does.

CREATE TABLE IF NOT EXISTS import_job_state (
  job_id            TEXT PRIMARY KEY,
  step              INTEGER NOT NULL DEFAULT 0,
  total             INTEGER NOT NULL DEFAULT 0,
  last_processed_id TEXT,
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','running','paused','completed','failed')),
  last_error        TEXT,
  started_at        TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at        TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_import_job_state_status
  ON import_job_state(status);
CREATE INDEX IF NOT EXISTS idx_import_job_state_updated_at
  ON import_job_state(updated_at);
