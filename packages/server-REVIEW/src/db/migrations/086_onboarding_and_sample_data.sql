-- ============================================================================
-- 086 — Day-1 Onboarding State + Sample Data Tracking (audit section 42)
-- ============================================================================
--
-- Purpose:
--   Backs the "Shop Owner — First Day Experience" feature set. A single-row
--   table tracks where the new shop is in their onboarding journey so the UI
--   can render contextual help, success celebrations, feature-discovery nudges,
--   and the sample-data toggle.
--
-- Why a single row?
--   Every tenant has exactly ONE onboarding state. The CHECK (id = 1) guard
--   makes this explicit and prevents bugs where code accidentally creates
--   a second row. The INSERT OR IGNORE below seeds the row for brand-new
--   tenants and is a no-op on upgraded tenants that already have it.
--
-- Why store sample_data_entities_json?
--   The sample data loader creates 5 customers + 10 tickets + 3 invoices
--   tagged `[Sample]`. When the user clicks "Remove sample data" we need to
--   delete EXACTLY those rows — not everything tagged `[Sample]` because a
--   real user might (perversely) type the word "Sample" into a tag field.
--   We store the {type, id} pairs as JSON so removal is byte-for-byte
--   reversible.
--
-- Milestone timestamps:
--   first_customer_at, first_ticket_at, etc. are set once by the first INSERT
--   of that kind and never updated afterward. This lets the UI fire a
--   confetti-and-toast celebration exactly once per milestone, and lets the
--   feature-discovery nudges compute "days since first customer" without
--   crawling the whole customers table.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS onboarding_state (
    id                         INTEGER PRIMARY KEY CHECK (id = 1),
    checklist_dismissed        INTEGER NOT NULL DEFAULT 0,
    shop_type                  TEXT,                                   -- phone_repair | computer_repair | watch_repair | general_electronics
    sample_data_loaded         INTEGER NOT NULL DEFAULT 0,
    sample_data_entities_json  TEXT,                                   -- JSON array of {type, id} for one-click removal
    first_customer_at          TEXT,
    first_ticket_at            TEXT,
    first_invoice_at           TEXT,
    first_payment_at           TEXT,
    first_review_at            TEXT,
    nudge_day3_seen            INTEGER NOT NULL DEFAULT 0,
    nudge_day5_seen            INTEGER NOT NULL DEFAULT 0,
    nudge_day7_seen            INTEGER NOT NULL DEFAULT 0,
    advanced_settings_unlocked INTEGER NOT NULL DEFAULT 0,
    intro_video_dismissed      INTEGER NOT NULL DEFAULT 0,
    created_at                 TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at                 TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Seed the single row. Idempotent on re-run.
INSERT OR IGNORE INTO onboarding_state (id) VALUES (1);
