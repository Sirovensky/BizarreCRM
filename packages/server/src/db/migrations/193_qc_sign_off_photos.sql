-- Migration 193 — WEB-UIUX-1092: multi-photo evidence on QC sign-offs.
-- Original `qc_sign_offs.working_photo_path` is a scalar TEXT, so techs can
-- only attach one photo per sign-off. Repair shops universally document
-- before + after; small-claims / warranty disputes hinge on the pair.
--
-- New table holds 0..N additional photos per sign-off, each labelled
-- ('before' / 'after' / 'damage' / 'free-form') and ordered. The legacy
-- `working_photo_path` stays as the primary/legacy slot — reads should
-- prefer the photo set when present and fall back to the scalar for
-- pre-migration rows.
CREATE TABLE IF NOT EXISTS qc_sign_off_photos (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  qc_sign_off_id  INTEGER NOT NULL REFERENCES qc_sign_offs(id) ON DELETE CASCADE,
  path            TEXT NOT NULL,
  label           TEXT,
  ord             INTEGER NOT NULL DEFAULT 0,
  created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_qc_sign_off_photos_signoff
  ON qc_sign_off_photos(qc_sign_off_id, ord);
