-- 174_qc_sign_offs_outcome.sql
-- WEB-UIUX-1083: extend qc_sign_offs to capture pass/fail outcome + reason.
-- Before this migration the modal could only record an all-green sign-off
-- (server validated every checklist item must `passed=true`). Techs who
-- discovered a fresh defect during QC (camera misaligned, port loose) had
-- to abandon the modal, change ticket status manually, and write a note,
-- losing the structured failure data the audit trail needs.
--
-- New columns are additive + nullable so existing rows stay valid; the
-- `outcome` column defaults to `'pass'` so pre-migration rows reflect the
-- previously-only-supported state.

ALTER TABLE qc_sign_offs
  ADD COLUMN outcome TEXT NOT NULL DEFAULT 'pass';
ALTER TABLE qc_sign_offs
  ADD COLUMN failure_reason TEXT;

CREATE INDEX IF NOT EXISTS idx_qc_sign_offs_outcome
  ON qc_sign_offs(outcome);
