-- Migration 181 — WEB-UIUX-812: persist rejected_at on estimates so the
-- portal Reject path has a timestamp to record (and reports can distinguish
-- declined quotes from never-sent ones). Mirrors the approved_at column
-- shape (nullable TEXT). No backfill — existing rejected rows (set via the
-- web detail page) get NULL until next state transition; the existing
-- /estimates list query already filters by status, not by rejected_at.
ALTER TABLE estimates ADD COLUMN rejected_at TEXT;
