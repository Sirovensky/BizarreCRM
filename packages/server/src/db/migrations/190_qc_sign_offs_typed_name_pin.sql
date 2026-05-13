-- Migration 190 — WEB-UIUX-1085: bind signature to the signing user's identity
-- so a manager handing their tablet to an apprentice doesn't get "signed by
-- manager" recorded on an apprentice's actual signature. Two new nullable
-- columns: `typed_name` (the signer types their full name alongside the
-- signature canvas; mismatched/blank still allowed in the audit row but
-- flagged as missing identity binding) and `pin_verified_at` (set when the
-- sign-off route verified the caller's PIN at submit time — recent
-- verification is a stronger repudiation defence than session-cookie alone).
ALTER TABLE qc_sign_offs ADD COLUMN typed_name TEXT;
ALTER TABLE qc_sign_offs ADD COLUMN pin_verified_at TEXT;
