-- 175_estimate_signatures_total_snapshot.sql
-- WEB-UIUX-811: snapshot the estimate's totals on the signature row so an
-- operator who edits line items post-approval can't change what the customer
-- "approved on [date]". Chargeback / dispute defense: the signature row
-- becomes the canonical "this is what the customer saw" record.
--
-- Columns are additive + nullable; pre-migration rows stay valid (NULL =
-- legacy signature with no captured totals).

ALTER TABLE estimate_signatures
  ADD COLUMN total_at_signing REAL;
ALTER TABLE estimate_signatures
  ADD COLUMN subtotal_at_signing REAL;
ALTER TABLE estimate_signatures
  ADD COLUMN tax_at_signing REAL;
