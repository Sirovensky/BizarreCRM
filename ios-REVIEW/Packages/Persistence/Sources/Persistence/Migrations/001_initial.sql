-- Initial schema. Tables mirror the Android/Room layout with SQL-native types.
-- See howtoIOS.md §19.2 for the full table list.

CREATE TABLE IF NOT EXISTS customer (
    id             INTEGER PRIMARY KEY NOT NULL,
    first_name     TEXT    NOT NULL,
    last_name      TEXT    NOT NULL,
    phone          TEXT,
    email          TEXT,
    notes          TEXT,
    created_at     TEXT    NOT NULL,
    updated_at     TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_customer_phone ON customer(phone);
CREATE INDEX IF NOT EXISTS idx_customer_email ON customer(email);

CREATE TABLE IF NOT EXISTS ticket (
    id              INTEGER PRIMARY KEY NOT NULL,
    display_id      TEXT    NOT NULL UNIQUE,
    customer_id     INTEGER NOT NULL,
    status          TEXT    NOT NULL,
    device_summary  TEXT,
    diagnosis       TEXT,
    total_cents     INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT    NOT NULL,
    updated_at      TEXT    NOT NULL,
    FOREIGN KEY (customer_id) REFERENCES customer(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_ticket_customer ON ticket(customer_id);
CREATE INDEX IF NOT EXISTS idx_ticket_status ON ticket(status);
CREATE INDEX IF NOT EXISTS idx_ticket_updated ON ticket(updated_at DESC);

CREATE TABLE IF NOT EXISTS inventory (
    id             INTEGER PRIMARY KEY NOT NULL,
    sku            TEXT    NOT NULL UNIQUE,
    name           TEXT    NOT NULL,
    barcode        TEXT,
    stock_qty      INTEGER NOT NULL DEFAULT 0,
    reorder_level  INTEGER NOT NULL DEFAULT 0,
    price_cents    INTEGER NOT NULL DEFAULT 0,
    cost_cents     INTEGER NOT NULL DEFAULT 0,
    updated_at     TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_inventory_barcode ON inventory(barcode);

CREATE TABLE IF NOT EXISTS sync_queue (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    kind           TEXT    NOT NULL,
    payload        TEXT    NOT NULL,
    enqueued_at    TEXT    NOT NULL,
    attempt_count  INTEGER NOT NULL DEFAULT 0,
    last_attempt   TEXT,
    last_error     TEXT
);

CREATE TABLE IF NOT EXISTS sync_metadata (
    key            TEXT    PRIMARY KEY,
    value          TEXT    NOT NULL
);
