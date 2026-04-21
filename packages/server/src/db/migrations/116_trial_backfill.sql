-- Migration 116: back-fill trial_started_at / trial_ends_at for existing tenants
--
-- Any active/provisioning tenant that was created before the trial columns were
-- added to the INSERT statement has NULL for both fields.  isTrialActive() returns
-- false when trial_ends_at IS NULL, so these tenants never get a Pro trial even
-- though they signed up when the 14-day trial was the documented offer.
--
-- We grant them 14 days from their created_at date so a shop that signed up
-- yesterday still gets the remainder of its trial; a shop older than 14 days
-- gets trial_ends_at in the past (trial already expired — correct behaviour).
--
-- Only touches tenants on plan='free' with no existing trial_ends_at value;
-- paid tenants (plan='pro') and tenants with an already-set trial_ends_at are
-- left untouched.

ALTER TABLE tenants ADD COLUMN IF NOT EXISTS trial_started_at TEXT;
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS trial_ends_at TEXT;

UPDATE tenants
SET
  trial_started_at = created_at,
  trial_ends_at    = datetime(created_at, '+14 days')
WHERE
  trial_ends_at IS NULL
  AND status NOT IN ('deleted', 'pending_deletion', 'quarantined')
  AND plan = 'free';
