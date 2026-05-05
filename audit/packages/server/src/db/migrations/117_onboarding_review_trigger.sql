-- ============================================================================
-- 117 — Onboarding Milestone: first_review_at trigger
-- ============================================================================
--
-- Purpose:
--   Automatically stamps `onboarding_state.first_review_at` the first time a
--   real customer review is inserted into `customer_reviews`. Mirrors the
--   pattern from migration 115 (onboarding milestone triggers).
--
-- No sample-data filter needed: loadSampleData() does not seed customer_reviews,
-- so every insert on this table is a real review.
--
-- Style follows migration 115_onboarding_milestone_triggers.sql.
-- ----------------------------------------------------------------------------

CREATE TRIGGER IF NOT EXISTS trg_onboarding_first_review
AFTER INSERT ON customer_reviews
BEGIN
  UPDATE onboarding_state
    SET first_review_at = datetime('now'),
        updated_at      = datetime('now')
    WHERE id = 1 AND first_review_at IS NULL;
END;
