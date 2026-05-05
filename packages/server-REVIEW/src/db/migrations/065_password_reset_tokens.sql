-- ENR-UX19: Password reset token columns on users table
ALTER TABLE users ADD COLUMN reset_token TEXT;
ALTER TABLE users ADD COLUMN reset_token_expires TEXT;
