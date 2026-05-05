-- ============================================================================
-- 085 — Per-tenant file-count quota (audit section 10, bug F4)
-- ============================================================================
--
-- Audit F4:
--   "Quota is bytes-only; no per-tenant file-count limit. Attacker can upload
--    millions of 1KB files."
--
-- Background:
--   `reserveStorage()` already enforces the byte-quota ceiling for a tenant,
--   but the on-disk inode count is unbounded. A tenant on the Free plan can
--   upload tens of millions of 1KB files, stay under the byte ceiling, and
--   still exhaust the host's inode table / crash the scraper that walks the
--   directory tree. We also need a cheap per-tenant sanity check that the
--   upload middleware can hit without stat'ing the entire tree on every
--   request.
--
-- Design:
--   store_config is a key/value table, so we don't add a dedicated column —
--   we reserve a single well-known key `file_count_quota` that stores the
--   allowed max file count for the tenant. The running counter itself lives
--   in the upload directory as a `.file_count` sentinel file (maintained by
--   fileUploadValidator.ts) to avoid a write-amplification hit on the
--   relational DB on every upload. This migration only seeds the default
--   ceiling; the counter file is created lazily on first upload.
--
--   Default 100 000 files is a safe ceiling for a busy shop (years of
--   activity) but low enough that an abusive script will hit it within
--   minutes. Admin can bump it through normal settings updates.
-- ----------------------------------------------------------------------------

INSERT OR IGNORE INTO store_config (key, value) VALUES
  ('file_count_quota', '100000');

-- No table changes required — store_config already exists from migration 001.
