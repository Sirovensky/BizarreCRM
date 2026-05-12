-- Migration 182 — WEB-UIUX-1067: capture cancellation reason + free-text note
-- on customer_subscriptions so retention analytics has signal beyond the bare
-- cancelled/active flip. Both columns are nullable so legacy cancellations
-- stay valid; the cancel route enforces an allow-listed reason going forward.
ALTER TABLE customer_subscriptions ADD COLUMN cancellation_reason TEXT;
ALTER TABLE customer_subscriptions ADD COLUMN cancellation_note TEXT;
