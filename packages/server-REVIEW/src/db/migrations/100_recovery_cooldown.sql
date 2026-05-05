-- SEC-H17: Track the last time a user completed a backup-code recovery
-- so we can apply a 24 h cooldown on role mutations. Rationale: if an
-- attacker gets a stolen backup code and a leaked email, the recovery
-- flow hands them a fresh session with the target user's role intact.
-- Without a cooldown they could immediately escalate (if the target
-- was admin) or do damage within the existing role before anyone
-- notices — cooldown forces a delay that gives the real user time to
-- notice the password-reset email and intervene.

ALTER TABLE users ADD COLUMN last_backup_recovery_at TEXT;
