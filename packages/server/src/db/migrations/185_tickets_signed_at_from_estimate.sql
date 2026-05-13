-- Migration 185 — WEB-UIUX-1472: when an estimate is converted to a ticket,
-- preserve the customer-signed evidence so the operator can answer "did the
-- customer sign before conversion?" without joining back to estimate_signatures.
-- Both columns are nullable so the legacy convert path (which never wrote
-- them) leaves them NULL.
ALTER TABLE tickets ADD COLUMN signed_at TEXT;
ALTER TABLE tickets ADD COLUMN signed_by_name TEXT;
