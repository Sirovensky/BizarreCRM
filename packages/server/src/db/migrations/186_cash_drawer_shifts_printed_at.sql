-- Migration 186 — WEB-UIUX-679: persist Z-report print audit. When a shift's
-- Z-report is printed (or "save as PDF"-equivalent) operators currently rely
-- on the paper. Now `printed_at` + `printed_by_user_id` are stamped so audit
-- + reprint history can answer "was this shift ever printed?". Nullable on
-- legacy rows — pre-migration shifts stay NULL until next print.
ALTER TABLE cash_drawer_shifts ADD COLUMN printed_at TEXT;
ALTER TABLE cash_drawer_shifts ADD COLUMN printed_by_user_id INTEGER;
