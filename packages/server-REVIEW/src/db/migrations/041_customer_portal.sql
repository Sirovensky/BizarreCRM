-- Customer Self-Service Portal: sessions, verification codes, and customer portal fields

-- Portal sessions (both quick-track and full account)
CREATE TABLE IF NOT EXISTS portal_sessions (
    id TEXT PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(id),
    token TEXT NOT NULL UNIQUE,
    scope TEXT NOT NULL DEFAULT 'ticket',
    ticket_id INTEGER REFERENCES tickets(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at TEXT NOT NULL,
    last_used_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_portal_sessions_token ON portal_sessions(token);
CREATE INDEX IF NOT EXISTS idx_portal_sessions_expires ON portal_sessions(expires_at);

-- Portal verification codes (one-time SMS codes for account creation)
CREATE TABLE IF NOT EXISTS portal_verification_codes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id INTEGER NOT NULL REFERENCES customers(id),
    phone TEXT NOT NULL,
    code TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at TEXT NOT NULL,
    used INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_portal_verify_customer ON portal_verification_codes(customer_id);

-- Add portal fields to customers table
ALTER TABLE customers ADD COLUMN portal_pin TEXT;
ALTER TABLE customers ADD COLUMN portal_verified INTEGER NOT NULL DEFAULT 0;
ALTER TABLE customers ADD COLUMN portal_created_at TEXT;
