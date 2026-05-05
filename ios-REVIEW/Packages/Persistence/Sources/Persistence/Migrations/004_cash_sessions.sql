-- §39 Cash Register & Z-Report — local-first sessions.
--
-- One row per shift-open on a given device+user. There can be only one
-- row with closed_at IS NULL; enforcement is done at the actor layer in
-- CashRegisterStore.openSession (SQLite partial unique index would reject
-- all trailing rows, but we want the open call to fail cleanly with a
-- typed error, not a raw constraint violation).
--
-- When the server endpoint `POST /pos/cash-sessions` lands, the sync
-- handler populates `server_id` so we can reconcile back to the shift row
-- the server created.

CREATE TABLE IF NOT EXISTS cash_sessions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    opened_by       INTEGER NOT NULL,
    opened_at       TEXT    NOT NULL,
    opening_float   INTEGER NOT NULL,           -- cents
    closed_at       TEXT,
    closed_by       INTEGER,
    counted_cash    INTEGER,                    -- cents at close
    expected_cash   INTEGER,                    -- opening_float + cash-in − cash-out + cash-tenders
    variance_cents  INTEGER,                    -- counted_cash − expected_cash
    notes           TEXT,
    server_id       TEXT,                       -- null until synced
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- Partial index is purely a perf assist — `currentSession()` scans this
-- index instead of the full table on every POS screen open.
CREATE INDEX IF NOT EXISTS idx_cash_sessions_open
    ON cash_sessions(closed_at) WHERE closed_at IS NULL;
