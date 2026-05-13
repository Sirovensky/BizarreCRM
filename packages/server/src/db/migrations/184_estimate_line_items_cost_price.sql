-- Migration 184 — WEB-UIUX-659: snapshot cost_price on every estimate line
-- so the margin reported at quote time doesn't silently drift after the
-- supplier raises the part cost. Null on legacy rows; new lines copy
-- inventory_items.cost_price at create + convert time.
ALTER TABLE estimate_line_items ADD COLUMN cost_price REAL;
