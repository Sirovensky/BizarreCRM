-- Track whether user has set their own password (vs admin-created without one)
ALTER TABLE users ADD COLUMN password_set INTEGER NOT NULL DEFAULT 1;
-- Existing users already have passwords set; new users created by admin will have password_set=0
