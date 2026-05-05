-- ============================================================================
-- 097 — Cascade cleanup triggers for enrichment tables (086-096)
-- ============================================================================
--
-- BACKGROUND
--   Migrations 086-096 added ~25 new child tables referencing customers,
--   tickets, invoices, inventory_items, and users. Almost none of them were
--   declared with `ON DELETE CASCADE`/`SET NULL` on the FK, and SQLite does
--   NOT support `ALTER TABLE … ADD CONSTRAINT` — you would have to rebuild
--   each table in place. That's a 25-table rewrite for a feature surface
--   that's still moving, so instead we install AFTER DELETE triggers on the
--   parent tables and cascade from there.
--
--   The normal routes (`DELETE /customers/:id`, `DELETE /tickets/:id`,
--   `DELETE /inventory/:id`) are soft deletes (`UPDATE … SET is_deleted=1`).
--   Triggers only fire on real row removal. The hard-delete paths that
--   currently bypass cleanup are:
--
--     1. `customers.routes.ts` GDPR erasure (`DELETE /:id/gdpr-erase`)
--     2. `services/sampleData.ts` sample-data removal (deletes invoices,
--         tickets, customers in a single transaction)
--     3. Any future admin "purge" flow
--
--   Without these triggers, each of those paths leaks orphan rows into
--   `loyalty_points`, `bench_timers`, `team_chat_channels`, etc. — exactly
--   the D1-D8 class of bug the original audit called out.
--
-- DESIGN NOTES
--
--   * ALL triggers are `CREATE TRIGGER IF NOT EXISTS` so re-running the
--     migration is a no-op on upgraded databases.
--
--   * Triggers are split per-parent for greppability. `trg_customer_del_*`,
--     `trg_ticket_del_*`, `trg_invoice_del_*`, `trg_inventory_del_*`.
--
--   * We DO NOT cascade on user deletes. Team tables (shift_schedules,
--     performance_reviews, payroll_periods, etc.) should intentionally
--     survive a user being removed — those rows are the audit trail. If a
--     future migration wants to nullify user_id we'll handle it there.
--
--   * We DO NOT cascade for tables the parent route already cleans up in
--     application code (customer_phones, customer_emails, etc. — those are
--     handled in customers.routes.ts lines 1679-1726 and the trigger would
--     be a no-op double-delete).
--
--   * Where the enrichment table is a BRIDGE (conversation_* keyed by
--     phone, sms_sentiment_history keyed by phone) we do not cascade
--     because the customer DELETE route already owns phone-scoped cleanup
--     (customers.routes.ts line 1711).
--
--   * Order of operations inside each trigger matters only when a child
--     table references another child table. None of the new tables do,
--     so statement order is purely alphabetical for readability.
--
--   * TypeScript callers never see these triggers — the cleanup happens
--     inside the same DELETE statement, inside whatever transaction the
--     app code is using. Audit logs on deletes still work, because the
--     app-level audit() call precedes the DELETE.
-- ----------------------------------------------------------------------------

-- ─── CUSTOMERS ─────────────────────────────────────────────────────────────
-- Enrichment tables referencing customers.id:
--   089  loyalty_points.customer_id
--   089  referrals.referrer_customer_id, referred_customer_id
--   089  customer_reviews.customer_id
--   090  nps_responses.customer_id
--   092  customer_segment_members.customer_id (already declared with CASCADE)
--   092  service_subscriptions.customer_id   (already declared with CASCADE)
--   092  campaign_sends.customer_id          (already declared with CASCADE)
--   095  payment_links.customer_id
--   095  installment_plans.customer_id
--   095  deposits.customer_id

CREATE TRIGGER IF NOT EXISTS trg_customer_del_enrichment_cleanup
AFTER DELETE ON customers
BEGIN
  DELETE FROM loyalty_points       WHERE customer_id = OLD.id;
  DELETE FROM referrals            WHERE referrer_customer_id = OLD.id
                                      OR referred_customer_id = OLD.id;
  DELETE FROM customer_reviews     WHERE customer_id = OLD.id;
  DELETE FROM nps_responses        WHERE customer_id = OLD.id;
  DELETE FROM payment_links        WHERE customer_id = OLD.id;
  DELETE FROM installment_plans    WHERE customer_id = OLD.id;
  DELETE FROM deposits             WHERE customer_id = OLD.id;
END;

-- ─── TICKETS ───────────────────────────────────────────────────────────────
-- Enrichment tables referencing tickets.id:
--   088  bench_timers.ticket_id
--   088  qc_sign_offs.ticket_id
--   088  parts_defect_reports.ticket_id        (nullable → set NULL)
--   089  warranty_certificates.ticket_id
--   089  customer_reviews.ticket_id            (nullable → set NULL; preserve review history)
--   089  ticket_photos_visibility.ticket_id
--   090  nps_responses.ticket_id               (nullable → set NULL)
--   091  inventory_serial_numbers.ticket_id    (nullable → set NULL; keep serial audit)
--   095  deposits.ticket_id                    (nullable → set NULL)
--   096  ticket_handoffs.ticket_id
--   096  team_mentions where context_type='ticket_note' AND context_id=OLD.id
--   096  team_chat_channels.ticket_id where kind='ticket'
--   096  team_chat_messages cascaded via channel delete below

CREATE TRIGGER IF NOT EXISTS trg_ticket_del_enrichment_cleanup
AFTER DELETE ON tickets
BEGIN
  -- Hard deletes (row lifecycle ends with the ticket)
  DELETE FROM bench_timers            WHERE ticket_id = OLD.id;
  DELETE FROM qc_sign_offs            WHERE ticket_id = OLD.id;
  DELETE FROM warranty_certificates   WHERE ticket_id = OLD.id;
  DELETE FROM ticket_photos_visibility WHERE ticket_id = OLD.id;
  DELETE FROM ticket_handoffs         WHERE ticket_id = OLD.id;
  DELETE FROM team_mentions
    WHERE context_type = 'ticket_note' AND context_id = OLD.id;

  -- Cascade into chat messages before deleting channels so we don't leave
  -- orphan rows in team_chat_messages. Done as two statements instead of a
  -- subquery DELETE so the ordering is explicit to reviewers.
  DELETE FROM team_chat_messages
    WHERE channel_id IN (
      SELECT id FROM team_chat_channels
      WHERE kind = 'ticket' AND ticket_id = OLD.id
    );
  DELETE FROM team_chat_channels
    WHERE kind = 'ticket' AND ticket_id = OLD.id;

  -- Nullify on tables whose rows should outlive the ticket (audit / history)
  UPDATE parts_defect_reports       SET ticket_id = NULL WHERE ticket_id = OLD.id;
  UPDATE customer_reviews           SET ticket_id = NULL WHERE ticket_id = OLD.id;
  UPDATE nps_responses              SET ticket_id = NULL WHERE ticket_id = OLD.id;
  UPDATE inventory_serial_numbers   SET ticket_id = NULL WHERE ticket_id = OLD.id;
  UPDATE deposits                   SET ticket_id = NULL WHERE ticket_id = OLD.id;
END;

-- ─── INVOICES ──────────────────────────────────────────────────────────────
-- Enrichment tables referencing invoices.id:
--   089  warranty_certificates — no FK to invoice
--   091  inventory_serial_numbers.invoice_id   (nullable → set NULL)
--   095  payment_links.invoice_id              (nullable → set NULL)
--   095  installment_plans.invoice_id          (nullable → set NULL)
--   095  dunning_runs.invoice_id               (hard delete — run log tied to invoice)
--   095  deposits.applied_to_invoice_id        (nullable → set NULL, keep the cash record)
--
-- invoice hard-deletes happen in sampleData.removeSampleDataByEntities and
-- nowhere else in production code, but that path is enough to require the
-- cleanup.

CREATE TRIGGER IF NOT EXISTS trg_invoice_del_enrichment_cleanup
AFTER DELETE ON invoices
BEGIN
  DELETE FROM dunning_runs                WHERE invoice_id = OLD.id;

  UPDATE inventory_serial_numbers
    SET invoice_id = NULL WHERE invoice_id = OLD.id;
  UPDATE payment_links
    SET invoice_id = NULL WHERE invoice_id = OLD.id;
  UPDATE installment_plans
    SET invoice_id = NULL WHERE invoice_id = OLD.id;
  UPDATE deposits
    SET applied_to_invoice_id = NULL WHERE applied_to_invoice_id = OLD.id;
END;

-- ─── INVENTORY ITEMS ───────────────────────────────────────────────────────
-- Enrichment tables referencing inventory_items.id:
--   088  parts_defect_reports.inventory_item_id
--   091  inventory_bin_assignments.inventory_item_id  (PK)
--   091  inventory_serial_numbers.inventory_item_id
--   091  inventory_shrinkage.inventory_item_id
--   091  supplier_prices.inventory_item_id
--   091  supplier_returns.inventory_item_id
--   091  inventory_compatibility.inventory_item_id
--   091  inventory_lot_warranty.inventory_item_id
--   091  inventory_auto_reorder_rules.inventory_item_id (PK)
--   091  stocktake_counts.inventory_item_id
--
-- inventory_items.DELETE route is a soft delete (is_active=0), but we still
-- install the trigger so that a future "purge deactivated items" admin job
-- or a direct DB maintenance query stays consistent.

CREATE TRIGGER IF NOT EXISTS trg_inventory_del_enrichment_cleanup
AFTER DELETE ON inventory_items
BEGIN
  DELETE FROM parts_defect_reports         WHERE inventory_item_id = OLD.id;
  DELETE FROM inventory_bin_assignments    WHERE inventory_item_id = OLD.id;
  DELETE FROM inventory_serial_numbers     WHERE inventory_item_id = OLD.id;
  DELETE FROM inventory_shrinkage          WHERE inventory_item_id = OLD.id;
  DELETE FROM supplier_prices              WHERE inventory_item_id = OLD.id;
  DELETE FROM supplier_returns             WHERE inventory_item_id = OLD.id;
  DELETE FROM inventory_compatibility      WHERE inventory_item_id = OLD.id;
  DELETE FROM inventory_lot_warranty       WHERE inventory_item_id = OLD.id;
  DELETE FROM inventory_auto_reorder_rules WHERE inventory_item_id = OLD.id;
  DELETE FROM stocktake_counts             WHERE inventory_item_id = OLD.id;
END;
