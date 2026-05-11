-- Migration 176 — BUGHUNT-2026-05-10-13: persist signed_at on estimates so
-- reports can distinguish today's signature from a stale one (status='signed'
-- alone collapses both into the same bucket).
--
-- Column is nullable on insert + backfilled lazily via the next /sign call
-- on the affected row (no offline backfill — the audit row in
-- estimate_signatures already carries signed_at for historical analysis).
ALTER TABLE estimates ADD COLUMN signed_at TEXT;
