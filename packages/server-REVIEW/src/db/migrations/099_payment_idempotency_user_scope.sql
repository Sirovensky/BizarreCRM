-- SEC-M41: Scope payment_idempotency rows to the user who issued the
-- idempotency key. Without user_id in the unique key, an attacker who
-- observed another user's (invoice_id, client_request_id) pair could
-- replay it from their own session and trigger the 'replayed charge'
-- happy path, leaking the transaction_id / amount of the original
-- payment. Adding user_id to the UNIQUE constraint forces replay to
-- match on both user AND request-id, which closes the cross-user read.

ALTER TABLE payment_idempotency ADD COLUMN user_id INTEGER REFERENCES users(id);

-- Backfill: the only sensible owner for existing rows is the invoice
-- creator. If that's NULL too (very old data), leave user_id NULL —
-- the application will treat NULL-user rows as "legacy, require fresh
-- idempotency row" via the WHERE user_id = ? IS NULL clause; see code.
UPDATE payment_idempotency
   SET user_id = (SELECT created_by FROM invoices WHERE invoices.id = payment_idempotency.invoice_id)
 WHERE user_id IS NULL;

-- Drop the narrow unique and add the wide one. SQLite can't drop
-- constraints in place, so recreate via the standard rename-and-copy
-- pattern. We keep status CHECK + FK identical.
CREATE TABLE IF NOT EXISTS payment_idempotency_new (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_id          INTEGER NOT NULL REFERENCES invoices(id),
  client_request_id   TEXT NOT NULL,
  user_id             INTEGER REFERENCES users(id),
  status              TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'completed', 'failed')),
  transaction_id      TEXT,
  payment_id          INTEGER REFERENCES payments(id),
  amount              REAL,
  error_message       TEXT,
  created_at          TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at          TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (invoice_id, client_request_id, user_id)
);

INSERT INTO payment_idempotency_new (id, invoice_id, client_request_id, user_id, status, transaction_id, payment_id, amount, error_message, created_at, updated_at)
SELECT id, invoice_id, client_request_id, user_id, status, transaction_id, payment_id, amount, error_message, created_at, updated_at
  FROM payment_idempotency;

DROP TABLE payment_idempotency;
ALTER TABLE payment_idempotency_new RENAME TO payment_idempotency;

CREATE INDEX IF NOT EXISTS idx_payment_idempotency_invoice_user
  ON payment_idempotency(invoice_id, user_id);
