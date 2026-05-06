-- Stamp the Getting Started sandbox checklist item from the server-side
-- training submit path, not from a client-only click.

ALTER TABLE onboarding_state ADD COLUMN sandbox_completed_at TEXT;
