-- ============================================================================
-- 098 — Schema Integrity Sweep (criticalaudit-rerun §42)
-- ============================================================================
--
-- Purely additive. After 97 migrations the cumulative schema drift around the
-- enrichment tables (086-096) needed a holistic pass to catch:
--
--   * Composite-index gaps where WHERE + ORDER BY can't share a single index
--   * Single-column FK indexes missing on enrichment tables — every cleanup
--     trigger from 097 has to scan-then-delete on tables whose FK column was
--     never indexed (sqlite query planner issues a full table scan inside
--     a trigger, which is the worst possible place for one)
--   * `store_config` keys that route handlers read but seed.ts never writes,
--     so the routes silently get a NULL value the first time the key is hit
--   * Tables that grow forever with no per-row retention discipline
--   * Enum-like TEXT columns that route handlers validate but the schema
--     does not back with a CHECK
--
-- DESIGN NOTES
--
--   * Every statement is `CREATE * IF NOT EXISTS` or `INSERT OR IGNORE`. The
--     migration is therefore idempotent — re-applying on a database that
--     already has any of these objects is a no-op.
--
--   * No CHECK constraints are added in this file. SQLite cannot ALTER an
--     existing table to add a CHECK without rebuilding it; that needs the
--     `writable_schema` rewrite trick from migration 074 and is deferred to
--     a future migration 099 that handles the table-rebuild family of fixes.
--
--   * No retention DELETEs run inside this migration. Retention sweeps belong
--     in the cron loop in index.ts, not in a migration. Documented as
--     follow-up at the bottom of this file.
--
--   * Trigger additions follow the pattern from 097 (AFTER DELETE on parent,
--     CREATE TRIGGER IF NOT EXISTS, alphabetical order inside the body).
--     Only the `users` cascade is new — 097 explicitly skipped it because
--     team tables were intentionally allowed to outlive a user, but we add
--     a *bench timer* cleanup here because timers are ephemeral session
--     state, not audit history, so they should not survive a user removal.
--
--   * Where a column is referenced in route code but missing from the schema
--     it gets an `ALTER TABLE ADD COLUMN` with a safe default. SQLite ALTER
--     ADD COLUMN with a literal default is non-locking and idempotent at the
--     migration-runner level (the runner skips this file once it's tracked
--     in `_migrations`).
-- ----------------------------------------------------------------------------

-- ────────────────────────────────────────────────────────────────────────────
-- A. Composite indexes for hot WHERE+ORDER BY paths
-- ────────────────────────────────────────────────────────────────────────────

-- A1. tickets list per customer in date order (tickets.routes.ts:3267, the
-- /customers/:id/tickets endpoint, and the sidebar customer card all run
-- "WHERE customer_id=? AND is_deleted=0 ORDER BY created_at DESC LIMIT N").
-- The standalone idx_tickets_customer_id forces a sort on the result rows;
-- this composite covers WHERE + ORDER BY in a single seek-and-walk.
CREATE INDEX IF NOT EXISTS idx_tickets_customer_active_created
  ON tickets(customer_id, is_deleted, created_at DESC);

-- A2. tickets assigned-to filter on the kanban board (tickets.routes.ts:478
-- view-all setting + assigned_to filter). Same composite shape.
CREATE INDEX IF NOT EXISTS idx_tickets_assigned_active_status
  ON tickets(assigned_to, is_deleted, status_id);

-- A3. invoices per customer with status filter (reports + customer card).
-- 056 added (customer_id, status, total) but the date-bounded variant used
-- by aging reports needs (customer_id, created_at).
CREATE INDEX IF NOT EXISTS idx_invoices_customer_created
  ON invoices(customer_id, created_at DESC);

-- A4. audit log query at settings.routes.ts:1648 filters by event +
-- user_id + created_at range and orders DESC. Existing single-column
-- indexes from migrations 022/053 cannot serve all three predicates.
CREATE INDEX IF NOT EXISTS idx_audit_logs_event_created
  ON audit_logs(event, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_created
  ON audit_logs(user_id, created_at DESC);

-- A5. notification_queue dispatcher: WHERE status='pending' AND
-- (scheduled_at IS NULL OR scheduled_at <= now()) ORDER BY created_at.
-- Two single-column indexes from 060 don't combine — partial index on
-- pending status keeps the table small for the dispatcher.
CREATE INDEX IF NOT EXISTS idx_nq_status_scheduled
  ON notification_queue(status, scheduled_at)
  WHERE status = 'pending';

-- A6. notification_retry_queue: comment in 070 explicitly says "would help"
-- but never created the composite. processRetryQueue() walks (next_retry_at
-- ASC) WHERE retry_count < max_retries.
CREATE INDEX IF NOT EXISTS idx_nrq_due
  ON notification_retry_queue(next_retry_at, retry_count);

-- A7. sms_retry_queue dispatcher: same shape as notification_retry_queue.
-- Migration 094 created idx_sms_retry_status and idx_sms_retry_next as
-- separate indexes.
CREATE INDEX IF NOT EXISTS idx_sms_retry_pending_due
  ON sms_retry_queue(status, next_retry_at)
  WHERE status = 'pending';

-- A8. employee_tips reporting: per-employee in date range. Existing
-- (employee_id) and (created_at) singles from 075 force a filesort.
CREATE INDEX IF NOT EXISTS idx_employee_tips_employee_created
  ON employee_tips(employee_id, created_at);

-- A9. expenses report by user in date range. expenses(user_id) + (date)
-- exist but not as a composite; the user-detail report runs both predicates.
CREATE INDEX IF NOT EXISTS idx_expenses_user_date
  ON expenses(user_id, date);

-- A10. POS transactions: customer_id lookup for the customer history page.
-- Migration 004 already created idx_pos_transactions_created on (created_at)
-- so we only need the customer scope here.
CREATE INDEX IF NOT EXISTS idx_pos_transactions_customer_id
  ON pos_transactions(customer_id);

-- A11. estimates auto-followup cron at index.ts walks
-- "WHERE sent_at IS NOT NULL AND followup_sent_at IS NULL AND sent_at < ?".
-- Add a partial index on the active follow-up window.
CREATE INDEX IF NOT EXISTS idx_estimates_followup_due
  ON estimates(sent_at)
  WHERE sent_at IS NOT NULL AND followup_sent_at IS NULL;

-- A12. marketing_campaigns scheduler: WHERE status='active' ORDER BY
-- last_run_at. The scheduler picks up "next campaign to run" by oldest
-- last_run_at among active rows.
CREATE INDEX IF NOT EXISTS idx_marketing_campaigns_active_run
  ON marketing_campaigns(status, last_run_at)
  WHERE status = 'active';

-- A13. customer_segments daily refresh: WHERE is_auto=1 ORDER BY
-- last_refreshed_at. Existing idx_customer_segments_is_auto only filters,
-- doesn't sort.
CREATE INDEX IF NOT EXISTS idx_customer_segments_auto_refresh
  ON customer_segments(is_auto, last_refreshed_at)
  WHERE is_auto = 1;

-- ────────────────────────────────────────────────────────────────────────────
-- B. Single-column FK indexes that the 097 cleanup triggers need
-- ────────────────────────────────────────────────────────────────────────────
--
-- 097 installs AFTER DELETE triggers on customers / tickets / invoices /
-- inventory_items that DELETE and UPDATE rows in enrichment tables. Without
-- a single-column index on the FK column, those statements force a full
-- scan inside the trigger body — which on a healthy shop with 100k rows in
-- inventory_serial_numbers means a cascading delete of one ticket can
-- sit-spin for seconds. Each of the indexes below covers a 097 trigger
-- target that was missing one.

-- 088 — bench_timers
CREATE INDEX IF NOT EXISTS idx_bench_timers_user_id
  ON bench_timers(user_id);
CREATE INDEX IF NOT EXISTS idx_bench_timers_ticket_device
  ON bench_timers(ticket_device_id);

-- 088 — qc_sign_offs
CREATE INDEX IF NOT EXISTS idx_qc_sign_offs_tech_user
  ON qc_sign_offs(tech_user_id);
CREATE INDEX IF NOT EXISTS idx_qc_sign_offs_ticket_device
  ON qc_sign_offs(ticket_device_id);

-- 088 — parts_defect_reports.ticket_id (097 nullifies it)
CREATE INDEX IF NOT EXISTS idx_parts_defect_reports_ticket
  ON parts_defect_reports(ticket_id);
CREATE INDEX IF NOT EXISTS idx_parts_defect_reports_user
  ON parts_defect_reports(reported_by_user_id);

-- 091 — inventory_serial_numbers.invoice_id / ticket_id (097 nullifies both).
-- Distinct prefix from the legacy inventory_serials table from migration 001
-- so we don't collide with idx_inventory_serials_item_id / _serial.
CREATE INDEX IF NOT EXISTS idx_inventory_serial_numbers_invoice
  ON inventory_serial_numbers(invoice_id);
CREATE INDEX IF NOT EXISTS idx_inventory_serial_numbers_ticket
  ON inventory_serial_numbers(ticket_id);

-- 091 — stocktake_counts: composite UNIQUE exists but the cleanup trigger
-- uses WHERE inventory_item_id only.
CREATE INDEX IF NOT EXISTS idx_stocktake_counts_item
  ON stocktake_counts(inventory_item_id);

-- 094 — sms_retry_queue.original_message_id (097 doesn't cascade — message
-- is the parent — but the inbox UI joins on it).
CREATE INDEX IF NOT EXISTS idx_sms_retry_original_message
  ON sms_retry_queue(original_message_id);

-- 094 — sms_sentiment_history.message_id (joined to sms_messages in the
-- conversation pane to render sentiment chips).
CREATE INDEX IF NOT EXISTS idx_sms_sentiment_message
  ON sms_sentiment_history(message_id);

-- 095 — installment_schedule.plan_id is indexed; add (plan_id, status) for
-- "find pending charges due today" cron.
CREATE INDEX IF NOT EXISTS idx_installment_schedule_plan_status
  ON installment_schedule(plan_id, status, due_date);

-- 095 — payment_links: expires_at sweep + token lookup. token already UNIQUE.
CREATE INDEX IF NOT EXISTS idx_payment_links_expires_at
  ON payment_links(expires_at)
  WHERE status = 'active' AND expires_at IS NOT NULL;

-- 096 — team_chat_messages.user_id for "messages by user" lookup and the
-- mention render path.
CREATE INDEX IF NOT EXISTS idx_team_chat_messages_user
  ON team_chat_messages(user_id);

-- 064 — invoices.parent_invoice_id (deposit → final lookup) and is_deposit
-- partial index for "open deposits" filter.
CREATE INDEX IF NOT EXISTS idx_invoices_parent
  ON invoices(parent_invoice_id)
  WHERE parent_invoice_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_invoices_is_deposit
  ON invoices(is_deposit)
  WHERE is_deposit = 1;

-- 026 — refunds.ticket_id (reports + customer history join) and status
CREATE INDEX IF NOT EXISTS idx_refunds_ticket
  ON refunds(ticket_id);
CREATE INDEX IF NOT EXISTS idx_refunds_status
  ON refunds(status);

-- 028 — gift_cards.status (active card list)
CREATE INDEX IF NOT EXISTS idx_gift_cards_status
  ON gift_cards(status);
CREATE INDEX IF NOT EXISTS idx_gift_card_transactions_card
  ON gift_card_transactions(gift_card_id);

-- 027 — rma_items has no FK index on rma_id (only the FK declaration).
CREATE INDEX IF NOT EXISTS idx_rma_items_rma_id
  ON rma_items(rma_id);

-- 026 — store_credit_transactions reference lookup
CREATE INDEX IF NOT EXISTS idx_store_credit_txn_reference
  ON store_credit_transactions(reference_type, reference_id);

-- 068 — customer_subscriptions.tier_id, subscription_payments.subscription_id
CREATE INDEX IF NOT EXISTS idx_customer_subscriptions_tier
  ON customer_subscriptions(tier_id);
CREATE INDEX IF NOT EXISTS idx_subscription_payments_subscription
  ON subscription_payments(subscription_id);

-- 029 — trade_ins.created_by report join
CREATE INDEX IF NOT EXISTS idx_trade_ins_created_by
  ON trade_ins(created_by);

-- 050 — leads composite for the assigned-to dashboard
CREATE INDEX IF NOT EXISTS idx_leads_assigned_status_active
  ON leads(assigned_to, status, is_deleted);

-- 052 — appointments.recurrence_parent_id (find children) + no_show stat
CREATE INDEX IF NOT EXISTS idx_appointments_recurrence_parent
  ON appointments(recurrence_parent_id)
  WHERE recurrence_parent_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appointments_no_show
  ON appointments(no_show)
  WHERE no_show = 1;

-- 001 — commissions ticket / invoice report joins
CREATE INDEX IF NOT EXISTS idx_commissions_ticket_id
  ON commissions(ticket_id);
CREATE INDEX IF NOT EXISTS idx_commissions_invoice_id
  ON commissions(invoice_id);

-- 043 — call_logs.user_id (user activity report) + status filter
CREATE INDEX IF NOT EXISTS idx_call_logs_user_id
  ON call_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_call_logs_status
  ON call_logs(status);

-- 081 — automation_run_log already has composites; add (automation_id, created_at)
-- for the per-automation history view that orders DESC by created_at.
CREATE INDEX IF NOT EXISTS idx_automation_run_log_auto_created
  ON automation_run_log(automation_id, created_at DESC);

-- 082 — webhook_delivery_failures: admin UI lists failures by event in
-- date-DESC order.
CREATE INDEX IF NOT EXISTS idx_webhook_delivery_failures_event_created
  ON webhook_delivery_failures(event, created_at DESC);

-- 069 — rate_limits cleanup needs a (category, first_attempt) index for the
-- per-category sweep. Existing (category, key) is for the lookup path only.
CREATE INDEX IF NOT EXISTS idx_rate_limits_category_first
  ON rate_limits(category, first_attempt);

-- 041 — portal_sessions.customer_id (for the "log out all sessions" path on
-- a customer pin reset).
CREATE INDEX IF NOT EXISTS idx_portal_sessions_customer
  ON portal_sessions(customer_id);

-- 002 — scrape_jobs.created_at for the recent-jobs admin list
CREATE INDEX IF NOT EXISTS idx_scrape_jobs_created_at
  ON scrape_jobs(created_at);

-- 094 — conversation_read_receipts.last_read_message_id join
CREATE INDEX IF NOT EXISTS idx_conv_read_message
  ON conversation_read_receipts(last_read_message_id);

-- ────────────────────────────────────────────────────────────────────────────
-- C. Cascade trigger for users → bench_timers
-- ────────────────────────────────────────────────────────────────────────────
--
-- 097 deliberately skipped cascading from the users table because team
-- tables (shifts, performance_reviews, payroll) are audit history that
-- should outlive a user removal. bench_timers is *not* audit history — it
-- is the live in-progress timer for an active session, and a row referring
-- to a deleted user is permanently wedged "Active" in the bench page's
-- "who is working right now" sidebar.
--
-- Hard-deleting users is rare (the normal flow is is_active=0), so this
-- trigger only fires on the GDPR-erase path or a direct admin DELETE.
-- We also wipe pos_training_sessions for the same reason — they hold a
-- fake-transaction blob that means nothing once the user is gone.
CREATE TRIGGER IF NOT EXISTS trg_user_del_session_cleanup
AFTER DELETE ON users
BEGIN
  DELETE FROM bench_timers          WHERE user_id = OLD.id;
  DELETE FROM pos_training_sessions WHERE user_id = OLD.id;
  -- Conversation assignments are nullified rather than deleted — the
  -- conversation row should survive but become unclaimed.
  UPDATE conversation_assignments  SET assigned_user_id = NULL WHERE assigned_user_id = OLD.id;
  -- Read receipts are scoped per-user; deleting them is the right call.
  DELETE FROM conversation_read_receipts WHERE user_id = OLD.id;
END;

-- ────────────────────────────────────────────────────────────────────────────
-- D. Onboarding state updated_at autotouch
-- ────────────────────────────────────────────────────────────────────────────
--
-- 086 declares onboarding_state.updated_at with a DEFAULT but no trigger to
-- maintain it on UPDATE, so the column value sticks at the row's first-write
-- value forever. Several onboarding routes report "updated 5 minutes ago"
-- as a UI hint and silently render a 6-month-old timestamp.
CREATE TRIGGER IF NOT EXISTS trg_onboarding_state_touch
AFTER UPDATE ON onboarding_state
FOR EACH ROW
WHEN NEW.updated_at IS OLD.updated_at
BEGIN
  UPDATE onboarding_state SET updated_at = datetime('now') WHERE id = NEW.id;
END;

-- ────────────────────────────────────────────────────────────────────────────
-- E. store_config keys referenced by routes but never seeded
-- ────────────────────────────────────────────────────────────────────────────
--
-- These keys are read by route handlers via
--   SELECT value FROM store_config WHERE key = ?
-- and the result is used unguarded as `?.value || <default>`. When the row
-- is missing the route silently uses the JS-side default — but the Settings
-- page renders a blank field for the same key, so admins think the feature
-- is disabled when it's actually enabled at the route level. Seeding the
-- defaults closes the gap so the UI matches behaviour from day one.

INSERT OR IGNORE INTO store_config (key, value) VALUES
  -- Branding (sms.routes.ts, voice.routes.ts, tickets.routes.ts use these)
  ('store_name',                      'Bizarre Electronics'),
  ('store_phone',                     ''),
  ('store_email',                     ''),
  ('store_address',                   ''),
  ('store_timezone',                  'America/Denver'),

  -- Auto-reply / business hours (sms.routes.ts:842-846)
  ('auto_reply_enabled',              'false'),
  ('auto_reply_message',              'Thanks for your message. We will reply during business hours.'),
  ('business_hours',                  '{"mon":[9,18],"tue":[9,18],"wed":[9,18],"thu":[9,18],"fri":[9,18],"sat":[10,16],"sun":null}'),

  -- Ticket workflow toggles (tickets.routes.ts)
  ('ticket_status_after_estimate',    ''),
  ('ticket_show_inventory',           'true'),
  ('ticket_show_parts_column',        'true'),
  ('ticket_auto_close_on_invoice',    'false'),
  ('ticket_auto_status_on_reply',     'false'),
  ('ticket_allow_edit_closed',        'false'),
  ('ticket_allow_edit_after_invoice', 'false'),
  ('ticket_allow_delete_after_invoice','false'),
  ('ticket_auto_remove_passcode',     'false'),
  ('ticket_copy_warranty_notes',      'false'),
  ('ticket_default_assignment',       'unassigned'),
  ('ticket_label_template',           ''),
  ('ticket_require_stopwatch',        'false'),
  ('ticket_all_employees_view_all',   'true'),
  ('ticket_timer_auto_start_status',  ''),
  ('ticket_timer_auto_stop_status',   ''),

  -- Repair workflow (tickets.routes.ts)
  ('repair_require_customer',         'true'),
  ('repair_require_pre_condition',    'false'),
  ('repair_require_post_condition',   'false'),
  ('repair_require_imei',             'false'),
  ('repair_require_parts',            'false'),
  ('repair_require_diagnostic',       'false'),
  ('repair_default_due_value',        '2'),
  ('repair_default_due_unit',         'days'),
  ('repair_default_warranty_value',   '90'),
  ('repair_default_warranty_unit',    'days'),
  ('repair_itemize_line_items',       'true'),
  ('repair_price_includes_parts',     'false'),
  ('repair_price_flat_adjustment',    '0'),
  ('repair_price_pct_adjustment',     '0'),

  -- Customer feedback (tickets.routes.ts:3266 + 1890-1892)
  ('feedback_enabled',                'false'),
  ('feedback_auto_sms',               'false'),
  ('feedback_sms_template',           'Hi {{customer_name}}, how was your repair experience? Reply 1-5 stars or click {{review_link}}.'),
  ('feedback_delay_hours',            '24'),

  -- POS quick check-in defaults (pos.routes.ts:1501)
  ('checkin_default_category',        'phone'),
  ('checkin_auto_print_label',        'false'),
  ('pos_require_referral',            'false'),
  ('pos_high_volume_drawer',          'false'),

  -- Lead pipeline (leads.routes.ts:200)
  ('lead_auto_assign',                'round_robin'),

  -- TV display
  ('tv_display_enabled',              'false');

-- ────────────────────────────────────────────────────────────────────────────
-- F. Backstop CHECK on rate_limits.category enum
-- ────────────────────────────────────────────────────────────────────────────
--
-- (Skipped — added to migration 099 with the rest of the table-rebuild
-- changes. SQLite refuses to add a CHECK to a populated table without
-- rewriting it via writable_schema.)

-- ────────────────────────────────────────────────────────────────────────────
-- DEFERRED to migration 099 (table rebuild required)
-- ────────────────────────────────────────────────────────────────────────────
--
-- The following changes need a writable_schema rebuild and are NOT in 098:
--
--   1. CHECK constraints on enum-like columns added by ALTER:
--      - rate_limits.category    IN ('login_ip','login_user','totp','pin')
--      - automation_run_log.status IN ('success','failure','skipped','loop_rejected')
--      - notification_queue.status IN ('pending','sent','failed','cancelled')
--      - sms_messages.status     IN ('pending','queued','sent','delivered','failed','scheduled','undelivered')
--      - sms_messages.direction  IN ('inbound','outbound')
--      - tickets.is_deleted      IN (0,1)   (and similar booleans elsewhere)
--      - invoices.status         IN ('draft','open','paid','partial','overdue','void','refunded')
--
--   2. Adding ON DELETE policies to FKs that were declared in migrations
--      088-096 without one. Specifically the FKs referenced from the 097
--      cleanup triggers should ideally become real FK constraints with
--      ON DELETE CASCADE / SET NULL — the trigger pattern is correct but
--      brittle (a future migration could declare a child table that the
--      author forgets to add to the trigger).
--
--   3. UNIQUE constraint on (customer_id, phone) for customers per-tenant
--      duplicate prevention. Today the only UNIQUE on customers is `code`,
--      and the duplicate-detector relies on application-level scans.
--
--   4. NOT NULL on referrals.referred_customer_id or a CHECK that at least
--      one of (referred_customer_id, referred_email, referred_phone) is set.
--
-- ────────────────────────────────────────────────────────────────────────────
-- DEFERRED to operations / cron (NOT a schema change)
-- ────────────────────────────────────────────────────────────────────────────
--
-- The following tables grow forever and need retention policies in the
-- daily 2 AM data-retention cron at index.ts:1454. Adding them here as a
-- schema-level trigger would cause every INSERT to scan the table, which
-- is the wrong tradeoff. They are listed so the next maintenance pass can
-- wire them into the existing forEachDb retention block:
--
--   - automation_run_log         keep 90 days
--   - webhook_delivery_failures  keep 60 days after admin acks
--   - rate_limits                keep 24h after first_attempt
--   - sms_retry_queue            keep 7 days after status='succeeded'|'cancelled'
--   - notification_queue         keep 30 days after status='sent'|'cancelled'
--   - notification_retry_queue   keep 7 days after retry_count >= max_retries
--   - report_snapshots           keep 1 year per (report_type, snapshot_date)
--   - import_rate_limits         keep 7 days after started_at
--   - cost_price_history         keep 5 years (financial audit)
--   - catalog_price_history      keep 1 year per supplier_catalog_id
