-- 2FA backup/recovery codes (hashed, one-time use)
ALTER TABLE users ADD COLUMN backup_codes TEXT;
-- JSON array of bcrypt-hashed codes, null until 2FA setup
