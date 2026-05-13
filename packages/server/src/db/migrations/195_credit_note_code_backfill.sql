-- Migration 195 — WEB-UIUX-1291: back-fill `credit_note_code` from legacy
-- free-form `reason` strings on credit-note rows that pre-date the structured
-- code/note columns. Reports now key on `credit_note_code`, so pre-FA-L8 rows
-- with NULL code were dropping out of cohorted refund analytics entirely.
--
-- Best-effort substring match against the canonical RefundReasonCode enum
-- (kept in lockstep with packages/web/src/components/billing/RefundReasonPicker.tsx).
-- Only touches rows where credit_note_code IS NULL so we never overwrite a
-- structured value with a string derived from `reason`.
--
-- The credit-note path on invoices is identified by `credit_note_for IS NOT NULL`
-- (the back-link to the original invoice). `notes` carries the legacy composed
-- `"Credit note: <reason>"` blob; we LOWER() it and match keywords.
--
-- Rows we can't classify stay NULL — reports still fall back to `notes` for
-- those, per the WEB-UIUX-1225 contract.
UPDATE invoices
   SET credit_note_code = CASE
     WHEN LOWER(COALESCE(notes, '')) LIKE '%defective%'                 THEN 'defective'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%dissatisf%'                 THEN 'dissatisfaction'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%wrong%item%'                THEN 'wrong_item'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%duplicate%charge%'          THEN 'duplicate_charge'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%duplicate%'                 THEN 'duplicate_charge'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%price%adjust%'              THEN 'price_adjustment'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%price%match%'               THEN 'price_adjustment'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%failed%repair%'             THEN 'failed_repair'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%lost%data%'                 THEN 'lost_data'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%delay%'                     THEN 'extended_delay'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%goodwill%'                  THEN 'goodwill_gesture'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%chargeback%'                THEN 'chargeback_prevention'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%warranty%'                  THEN 'warranty_invocation'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%cancel%service%'            THEN 'cancelled_service'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%cancel%'                    THEN 'cancelled_service'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%exchange%'                  THEN 'exchange_no_refund'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%tax%adjust%'                THEN 'tax_adjustment'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%shipping%'                  THEN 'shipping_issue'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%loyalty%'                   THEN 'loyalty_promo_retroactive'
     WHEN LOWER(COALESCE(notes, '')) LIKE '%promo%'                     THEN 'loyalty_promo_retroactive'
     ELSE NULL
   END
 WHERE credit_note_for IS NOT NULL
   AND credit_note_code IS NULL
   AND notes IS NOT NULL;
