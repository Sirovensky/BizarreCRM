-- BL6, BL7, BL8: Payment idempotency + signature file audit trail
--
-- Fixes:
--   BL6: services/blockchyp.ts#processPayment built transactionRef as
--        "payment-${ticketOrderId}-${Date.now()}". Two payment attempts in the
--        same millisecond produced the same ref; BlockChyp then treated the
--        second attempt as a retry OF A DIFFERENT ATTEMPT and double-charged.
--        Fix: allocate a monotonic counter per transaction ref via the
--        counters table (name = 'blockchyp_transaction_ref') and append
--        8 random bytes. See utils/counters.ts + services/blockchyp.ts.
--
--   BL7: routes/blockchyp.routes.ts#POST /process-payment had no per-invoice
--        idempotency. A retry or double-click submitted two real charges.
--        Fix: payment_idempotency table keyed by (invoice_id, client_request_id).
--        Client must supply an `idempotency_key` (UUID) per payment attempt.
--        First request inserts a 'pending' row, succeeds, and updates to
--        'completed'. Duplicate key for the same invoice returns 409.
--
--   BL8: Captured signature files were saved with a random filename but never
--        linked back to the payment row, and never cleaned up on failed / voided
--        payments. Fix: add a `signature_file_path` column to payments (the
--        existing `signature_file` column only stored the bare filename via
--        ticketing code paths; we keep that for backwards compatibility and add
--        an explicit path column + audit log entries on void/delete).

-- ----------------------------------------------------------------------------
-- BL6: Counter row for BlockChyp transaction ref uniqueness
-- ----------------------------------------------------------------------------
-- INSERT OR IGNORE so reruns are safe. The existing counters row (if any)
-- is preserved; allocateCounter() will increment it atomically.
INSERT OR IGNORE INTO counters (name, value) VALUES ('blockchyp_transaction_ref', 0);

-- ----------------------------------------------------------------------------
-- BL7: payment_idempotency table
-- ----------------------------------------------------------------------------
-- One row per (invoice_id, client_request_id). Clients generate client_request_id
-- as a UUIDv4 on the "Charge" button and re-use it for the life of the attempt,
-- so retries collapse into one charge.
--
-- Status values:
--   'pending'    — reserved the key, BlockChyp call in flight.
--   'completed'  — charge succeeded, payment row written.
--   'failed'     — BlockChyp declined or errored. Client may retry with a NEW key.
--
-- transaction_id is filled in after BlockChyp returns and helps audit trails
-- when a payment row is later voided.
CREATE TABLE IF NOT EXISTS payment_idempotency (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_id          INTEGER NOT NULL REFERENCES invoices(id),
  client_request_id   TEXT NOT NULL,
  status              TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'completed', 'failed')),
  transaction_id      TEXT,
  payment_id          INTEGER REFERENCES payments(id),
  amount              REAL,
  error_message       TEXT,
  created_at          TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at          TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (invoice_id, client_request_id)
);

CREATE INDEX IF NOT EXISTS idx_payment_idempotency_invoice_id ON payment_idempotency(invoice_id);
CREATE INDEX IF NOT EXISTS idx_payment_idempotency_status     ON payment_idempotency(status);
CREATE INDEX IF NOT EXISTS idx_payment_idempotency_created_at ON payment_idempotency(created_at);

-- ----------------------------------------------------------------------------
-- BL8: Signature file path column on payments
-- ----------------------------------------------------------------------------
-- `signature_file` already exists from migration 040 (stores the bare filename).
-- Add `signature_file_path` for an absolute-path audit trail so cleanup on
-- void / refund can delete the exact file without re-resolving uploadsPath.
ALTER TABLE payments ADD COLUMN signature_file_path TEXT;
