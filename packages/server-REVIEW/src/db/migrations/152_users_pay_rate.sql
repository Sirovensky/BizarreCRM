-- 152_users_pay_rate.sql
-- WEB-S6-014: Add hourly pay_rate column to users table.
-- REAL affinity → stored as IEEE-754 float. NULL = not configured.
-- The column is intentionally admin-only; the employees list endpoint
-- and the new PATCH /employees/:id route expose it only to admins.
ALTER TABLE users ADD COLUMN pay_rate REAL DEFAULT NULL;
