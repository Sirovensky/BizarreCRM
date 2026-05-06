-- WEB-UNWIRED-039: durable link between a loaner return fee and the real
-- billable invoice/payment rows created during return.
CREATE TABLE IF NOT EXISTS loaner_return_charges (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  loaner_history_id   INTEGER NOT NULL REFERENCES loaner_history(id) ON DELETE CASCADE,
  loaner_device_id    INTEGER NOT NULL REFERENCES loaner_devices(id),
  customer_id         INTEGER NOT NULL REFERENCES customers(id),
  ticket_id           INTEGER REFERENCES tickets(id),
  invoice_id          INTEGER NOT NULL REFERENCES invoices(id),
  payment_id          INTEGER REFERENCES payments(id),
  amount              REAL NOT NULL CHECK(amount > 0),
  amount_paid         REAL NOT NULL DEFAULT 0 CHECK(amount_paid >= 0),
  amount_due          REAL NOT NULL DEFAULT 0 CHECK(amount_due >= 0),
  status              TEXT NOT NULL CHECK(status IN ('unpaid', 'paid')),
  payment_method      TEXT,
  payment_reference   TEXT,
  notes               TEXT,
  created_by_user_id  INTEGER NOT NULL REFERENCES users(id),
  created_at          TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_loaner_return_charges_history
  ON loaner_return_charges(loaner_history_id);
CREATE INDEX IF NOT EXISTS idx_loaner_return_charges_loaner
  ON loaner_return_charges(loaner_device_id);
CREATE INDEX IF NOT EXISTS idx_loaner_return_charges_customer
  ON loaner_return_charges(customer_id);
CREATE INDEX IF NOT EXISTS idx_loaner_return_charges_ticket
  ON loaner_return_charges(ticket_id);
CREATE INDEX IF NOT EXISTS idx_loaner_return_charges_invoice
  ON loaner_return_charges(invoice_id);
