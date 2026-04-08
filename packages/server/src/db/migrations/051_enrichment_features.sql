-- ENR-T8: ticket_links table for related/linked tickets
CREATE TABLE IF NOT EXISTS ticket_links (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    ticket_id_a   INTEGER NOT NULL REFERENCES tickets(id),
    ticket_id_b   INTEGER NOT NULL REFERENCES tickets(id),
    link_type     TEXT NOT NULL DEFAULT 'related' CHECK(link_type IN ('related', 'duplicate', 'warranty_followup')),
    created_by    INTEGER REFERENCES users(id),
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_ticket_links_a ON ticket_links(ticket_id_a);
CREATE INDEX IF NOT EXISTS idx_ticket_links_b ON ticket_links(ticket_id_b);

-- ENR-T13: is_warranty flag on tickets for warranty cases
ALTER TABLE tickets ADD COLUMN is_warranty INTEGER NOT NULL DEFAULT 0;

-- ENR-I2: payment_type on payments (deposit vs regular payment)
ALTER TABLE payments ADD COLUMN payment_type TEXT NOT NULL DEFAULT 'payment' CHECK(payment_type IN ('payment', 'deposit'));

-- ENR-I9: credit_note_for on invoices (links credit note to original invoice)
ALTER TABLE invoices ADD COLUMN credit_note_for INTEGER REFERENCES invoices(id);
