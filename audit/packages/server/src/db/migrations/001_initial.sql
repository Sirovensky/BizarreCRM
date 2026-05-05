-- ============================================================================
-- Bizarre CRM - Initial Database Migration
-- Version: 001
-- Description: Full schema for repair shop CRM
-- ============================================================================

PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

-- ============================================================================
-- 1. STORE CONFIGURATION (key-value settings)
-- ============================================================================
CREATE TABLE IF NOT EXISTS store_config (
    key   TEXT PRIMARY KEY,
    value TEXT
);

-- ============================================================================
-- 2. USERS
-- ============================================================================
CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    username      TEXT NOT NULL UNIQUE,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    pin           TEXT,
    first_name    TEXT NOT NULL DEFAULT '',
    last_name     TEXT NOT NULL DEFAULT '',
    role          TEXT NOT NULL DEFAULT 'technician',
    avatar_url    TEXT,
    is_active     INTEGER NOT NULL DEFAULT 1,
    permissions   TEXT DEFAULT '{}',                          -- JSON
    created_at    TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============================================================================
-- 3. SESSIONS
-- ============================================================================
CREATE TABLE IF NOT EXISTS sessions (
    id          TEXT PRIMARY KEY,                              -- UUID
    user_id     INTEGER NOT NULL REFERENCES users(id),
    device_info TEXT,
    expires_at  TEXT NOT NULL,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_sessions_user_id    ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions(expires_at);

-- ============================================================================
-- 4. CUSTOMER GROUPS (referenced by customers)
-- ============================================================================
CREATE TABLE IF NOT EXISTS customer_groups (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT NOT NULL UNIQUE,
    discount_pct REAL NOT NULL DEFAULT 0,
    description  TEXT,
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============================================================================
-- 5. TAX CLASSES (referenced by many tables)
-- ============================================================================
CREATE TABLE IF NOT EXISTS tax_classes (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL UNIQUE,
    rate       REAL NOT NULL DEFAULT 0,
    is_default INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============================================================================
-- 6. CUSTOMERS
-- ============================================================================
CREATE TABLE IF NOT EXISTS customers (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    code              TEXT UNIQUE,
    first_name        TEXT NOT NULL DEFAULT '',
    last_name         TEXT NOT NULL DEFAULT '',
    title             TEXT,
    organization      TEXT,
    type              TEXT NOT NULL DEFAULT 'individual',
    email             TEXT,
    phone             TEXT,
    mobile            TEXT,
    address1          TEXT,
    address2          TEXT,
    city              TEXT,
    state             TEXT,
    postcode          TEXT,
    country           TEXT,
    contact_person    TEXT,
    contact_relation  TEXT,
    driving_license   TEXT,
    license_image     TEXT,
    id_type           TEXT,
    id_number         TEXT,
    referred_by       TEXT,
    customer_group_id INTEGER REFERENCES customer_groups(id),
    tax_number        TEXT,
    tax_class_id      INTEGER REFERENCES tax_classes(id),
    email_opt_in      INTEGER NOT NULL DEFAULT 0,
    sms_opt_in        INTEGER NOT NULL DEFAULT 0,
    comments          TEXT,
    avatar_url        TEXT,
    source            TEXT,
    tags              TEXT DEFAULT '[]',                       -- JSON
    is_deleted        INTEGER NOT NULL DEFAULT 0,
    created_at        TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at        TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_customers_code         ON customers(code);
CREATE INDEX IF NOT EXISTS idx_customers_email        ON customers(email);
CREATE INDEX IF NOT EXISTS idx_customers_phone        ON customers(phone);
CREATE INDEX IF NOT EXISTS idx_customers_mobile       ON customers(mobile);
CREATE INDEX IF NOT EXISTS idx_customers_organization ON customers(organization);
CREATE INDEX IF NOT EXISTS idx_customers_group_id     ON customers(customer_group_id);
CREATE INDEX IF NOT EXISTS idx_customers_is_deleted   ON customers(is_deleted);

-- ============================================================================
-- 7. CUSTOMER PHONES
-- ============================================================================
CREATE TABLE IF NOT EXISTS customer_phones (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    phone       TEXT NOT NULL,
    label       TEXT,
    is_primary  INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_customer_phones_customer_id ON customer_phones(customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_phones_phone       ON customer_phones(phone);

-- ============================================================================
-- 8. CUSTOMER EMAILS
-- ============================================================================
CREATE TABLE IF NOT EXISTS customer_emails (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    email       TEXT NOT NULL,
    label       TEXT,
    is_primary  INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_customer_emails_customer_id ON customer_emails(customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_emails_email       ON customer_emails(email);

-- ============================================================================
-- 9. CUSTOMER ASSETS
-- ============================================================================
CREATE TABLE IF NOT EXISTS customer_assets (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    device_type TEXT,
    serial      TEXT,
    imei        TEXT,
    color       TEXT,
    notes       TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_customer_assets_customer_id ON customer_assets(customer_id);

-- ============================================================================
-- 10. TICKET STATUSES
-- ============================================================================
CREATE TABLE IF NOT EXISTS ticket_statuses (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    name                  TEXT NOT NULL UNIQUE,
    color                 TEXT NOT NULL DEFAULT '#6b7280',
    sort_order            INTEGER NOT NULL DEFAULT 0,
    is_default            INTEGER NOT NULL DEFAULT 0,
    is_closed             INTEGER NOT NULL DEFAULT 0,
    is_cancelled          INTEGER NOT NULL DEFAULT 0,
    notify_customer       INTEGER NOT NULL DEFAULT 0,
    notification_template TEXT,
    created_at            TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at            TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============================================================================
-- 11. SUPPLIERS (referenced by inventory_items and purchase_orders)
-- ============================================================================
CREATE TABLE IF NOT EXISTS suppliers (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT NOT NULL,
    contact_name TEXT,
    email        TEXT,
    phone        TEXT,
    address      TEXT,
    notes        TEXT,
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============================================================================
-- 12. INVENTORY ITEMS
-- ============================================================================
CREATE TABLE IF NOT EXISTS inventory_items (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    sku           TEXT UNIQUE,
    upc           TEXT,
    name          TEXT NOT NULL,
    description   TEXT,
    item_type     TEXT NOT NULL DEFAULT 'product' CHECK (item_type IN ('product', 'part', 'service')),
    category      TEXT,
    manufacturer  TEXT,
    device_type   TEXT,
    cost_price    REAL NOT NULL DEFAULT 0,
    retail_price  REAL NOT NULL DEFAULT 0,
    in_stock      INTEGER NOT NULL DEFAULT 0,
    reorder_level INTEGER NOT NULL DEFAULT 0,
    stock_warning INTEGER NOT NULL DEFAULT 0,
    tax_class_id  INTEGER REFERENCES tax_classes(id),
    tax_inclusive  INTEGER NOT NULL DEFAULT 0,
    is_serialized INTEGER NOT NULL DEFAULT 0,
    supplier_id   INTEGER REFERENCES suppliers(id),
    image_url     TEXT,
    is_active     INTEGER NOT NULL DEFAULT 1,
    created_at    TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_inventory_items_sku       ON inventory_items(sku);
CREATE INDEX IF NOT EXISTS idx_inventory_items_upc       ON inventory_items(upc);
CREATE INDEX IF NOT EXISTS idx_inventory_items_item_type ON inventory_items(item_type);
CREATE INDEX IF NOT EXISTS idx_inventory_items_category  ON inventory_items(category);
CREATE INDEX IF NOT EXISTS idx_inventory_items_name      ON inventory_items(name);
CREATE INDEX IF NOT EXISTS idx_inventory_items_is_active ON inventory_items(is_active);

-- ============================================================================
-- 13. REFERRAL SOURCES (referenced by tickets/leads)
-- ============================================================================
CREATE TABLE IF NOT EXISTS referral_sources (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL UNIQUE,
    sort_order INTEGER NOT NULL DEFAULT 0
);

-- ============================================================================
-- 14. PAYMENT METHODS
-- ============================================================================
CREATE TABLE IF NOT EXISTS payment_methods (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL UNIQUE,
    is_active  INTEGER NOT NULL DEFAULT 1,
    sort_order INTEGER NOT NULL DEFAULT 0
);

-- ============================================================================
-- 15. LOANER DEVICES
-- ============================================================================
CREATE TABLE IF NOT EXISTS loaner_devices (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL,
    serial     TEXT,
    imei       TEXT,
    condition  TEXT,
    status     TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'loaned', 'retired')),
    notes      TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============================================================================
-- 16. INVOICES (forward-declared for ticket FK)
-- ============================================================================
CREATE TABLE IF NOT EXISTS invoices (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id        TEXT NOT NULL UNIQUE,
    ticket_id       INTEGER,                                  -- FK added after tickets table
    customer_id     INTEGER NOT NULL REFERENCES customers(id),
    status          TEXT NOT NULL DEFAULT 'draft',
    subtotal        REAL NOT NULL DEFAULT 0,
    discount        REAL NOT NULL DEFAULT 0,
    discount_reason TEXT,
    total_tax       REAL NOT NULL DEFAULT 0,
    total           REAL NOT NULL DEFAULT 0,
    amount_paid     REAL NOT NULL DEFAULT 0,
    amount_due      REAL NOT NULL DEFAULT 0,
    due_date        TEXT,
    notes           TEXT,
    created_by      INTEGER NOT NULL REFERENCES users(id),
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_invoices_order_id    ON invoices(order_id);
CREATE INDEX IF NOT EXISTS idx_invoices_ticket_id   ON invoices(ticket_id);
CREATE INDEX IF NOT EXISTS idx_invoices_customer_id ON invoices(customer_id);
CREATE INDEX IF NOT EXISTS idx_invoices_status      ON invoices(status);

-- ============================================================================
-- 17. ESTIMATES (forward-declared for ticket FK)
-- ============================================================================
CREATE TABLE IF NOT EXISTS estimates (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id            TEXT NOT NULL UNIQUE,
    customer_id         INTEGER NOT NULL REFERENCES customers(id),
    status              TEXT NOT NULL DEFAULT 'draft',
    subtotal            REAL NOT NULL DEFAULT 0,
    discount            REAL NOT NULL DEFAULT 0,
    total_tax           REAL NOT NULL DEFAULT 0,
    total               REAL NOT NULL DEFAULT 0,
    valid_until         TEXT,
    notes               TEXT,
    approval_token      TEXT,
    approved_at         TEXT,
    converted_ticket_id INTEGER,                              -- FK added after tickets table
    created_by          INTEGER NOT NULL REFERENCES users(id),
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_estimates_order_id    ON estimates(order_id);
CREATE INDEX IF NOT EXISTS idx_estimates_customer_id ON estimates(customer_id);
CREATE INDEX IF NOT EXISTS idx_estimates_status      ON estimates(status);

-- ============================================================================
-- 18. TICKETS
-- ============================================================================
CREATE TABLE IF NOT EXISTS tickets (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id        TEXT NOT NULL UNIQUE,
    customer_id     INTEGER NOT NULL REFERENCES customers(id),
    status_id       INTEGER NOT NULL REFERENCES ticket_statuses(id),
    assigned_to     INTEGER REFERENCES users(id),
    subtotal        REAL NOT NULL DEFAULT 0,
    discount        REAL NOT NULL DEFAULT 0,
    discount_reason TEXT,
    total_tax       REAL NOT NULL DEFAULT 0,
    total           REAL NOT NULL DEFAULT 0,
    source          TEXT,
    referral_source TEXT,
    signature       TEXT,
    labels          TEXT DEFAULT '[]',                         -- JSON
    due_on          TEXT,
    invoice_id      INTEGER REFERENCES invoices(id),
    estimate_id     INTEGER REFERENCES estimates(id),
    is_deleted      INTEGER NOT NULL DEFAULT 0,
    created_by      INTEGER NOT NULL REFERENCES users(id),
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_tickets_order_id    ON tickets(order_id);
CREATE INDEX IF NOT EXISTS idx_tickets_customer_id ON tickets(customer_id);
CREATE INDEX IF NOT EXISTS idx_tickets_status_id   ON tickets(status_id);
CREATE INDEX IF NOT EXISTS idx_tickets_assigned_to ON tickets(assigned_to);
CREATE INDEX IF NOT EXISTS idx_tickets_created_by  ON tickets(created_by);
CREATE INDEX IF NOT EXISTS idx_tickets_due_on      ON tickets(due_on);
CREATE INDEX IF NOT EXISTS idx_tickets_is_deleted  ON tickets(is_deleted);
CREATE INDEX IF NOT EXISTS idx_tickets_created_at  ON tickets(created_at);

-- ============================================================================
-- 19. TICKET DEVICES
-- ============================================================================
CREATE TABLE IF NOT EXISTS ticket_devices (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    ticket_id        INTEGER NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    device_name      TEXT NOT NULL DEFAULT '',
    device_type      TEXT,
    imei             TEXT,
    serial           TEXT,
    security_code    TEXT,
    color            TEXT,
    network          TEXT,
    status_id        INTEGER REFERENCES ticket_statuses(id),
    assigned_to      INTEGER REFERENCES users(id),
    service_id       INTEGER REFERENCES inventory_items(id),
    price            REAL NOT NULL DEFAULT 0,
    line_discount    REAL NOT NULL DEFAULT 0,
    tax_amount       REAL NOT NULL DEFAULT 0,
    tax_class_id     INTEGER REFERENCES tax_classes(id),
    tax_inclusive     INTEGER NOT NULL DEFAULT 0,
    total            REAL NOT NULL DEFAULT 0,
    warranty         INTEGER NOT NULL DEFAULT 0,
    warranty_days    INTEGER NOT NULL DEFAULT 0,
    due_on           TEXT,
    collected_date   TEXT,
    device_location  TEXT,
    additional_notes TEXT,
    pre_conditions   TEXT DEFAULT '{}',                        -- JSON
    post_conditions  TEXT DEFAULT '{}',                        -- JSON
    loaner_device_id INTEGER REFERENCES loaner_devices(id),
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_ticket_devices_ticket_id  ON ticket_devices(ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_devices_status_id  ON ticket_devices(status_id);
CREATE INDEX IF NOT EXISTS idx_ticket_devices_assigned   ON ticket_devices(assigned_to);

-- ============================================================================
-- 20. TICKET DEVICE PARTS
-- ============================================================================
CREATE TABLE IF NOT EXISTS ticket_device_parts (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    ticket_device_id  INTEGER NOT NULL REFERENCES ticket_devices(id) ON DELETE CASCADE,
    inventory_item_id INTEGER NOT NULL REFERENCES inventory_items(id),
    quantity          INTEGER NOT NULL DEFAULT 1,
    price             REAL NOT NULL DEFAULT 0,
    warranty          INTEGER NOT NULL DEFAULT 0,
    serial            TEXT,
    created_at        TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at        TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_ticket_device_parts_device_id ON ticket_device_parts(ticket_device_id);
CREATE INDEX IF NOT EXISTS idx_ticket_device_parts_item_id   ON ticket_device_parts(inventory_item_id);

-- ============================================================================
-- 21. TICKET PHOTOS
-- ============================================================================
CREATE TABLE IF NOT EXISTS ticket_photos (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    ticket_device_id INTEGER NOT NULL REFERENCES ticket_devices(id) ON DELETE CASCADE,
    type             TEXT NOT NULL DEFAULT 'pre' CHECK (type IN ('pre', 'post')),
    file_path        TEXT NOT NULL,
    caption          TEXT,
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_ticket_photos_device_id ON ticket_photos(ticket_device_id);

-- ============================================================================
-- 22. TICKET NOTES
-- ============================================================================
CREATE TABLE IF NOT EXISTS ticket_notes (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    ticket_id        INTEGER NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    ticket_device_id INTEGER REFERENCES ticket_devices(id),
    user_id          INTEGER NOT NULL REFERENCES users(id),
    type             TEXT NOT NULL DEFAULT 'internal' CHECK (type IN ('internal', 'diagnostic', 'email')),
    content          TEXT NOT NULL,
    is_flagged       INTEGER NOT NULL DEFAULT 0,
    parent_id        INTEGER REFERENCES ticket_notes(id),
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_ticket_notes_ticket_id ON ticket_notes(ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_notes_device_id ON ticket_notes(ticket_device_id);
CREATE INDEX IF NOT EXISTS idx_ticket_notes_user_id   ON ticket_notes(user_id);

-- ============================================================================
-- 23. TICKET HISTORY
-- ============================================================================
CREATE TABLE IF NOT EXISTS ticket_history (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    ticket_id   INTEGER NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    user_id     INTEGER REFERENCES users(id),
    action      TEXT NOT NULL,
    description TEXT,
    old_value   TEXT,
    new_value   TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_ticket_history_ticket_id ON ticket_history(ticket_id);

-- ============================================================================
-- 24. CHECKLIST TEMPLATES
-- ============================================================================
CREATE TABLE IF NOT EXISTS checklist_templates (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    device_type TEXT,
    items       TEXT NOT NULL DEFAULT '[]',                    -- JSON
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============================================================================
-- 25. TICKET CHECKLISTS
-- ============================================================================
CREATE TABLE IF NOT EXISTS ticket_checklists (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    ticket_device_id      INTEGER NOT NULL REFERENCES ticket_devices(id) ON DELETE CASCADE,
    checklist_template_id INTEGER NOT NULL REFERENCES checklist_templates(id),
    items                 TEXT NOT NULL DEFAULT '[]',          -- JSON
    created_at            TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at            TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_ticket_checklists_device_id ON ticket_checklists(ticket_device_id);

-- ============================================================================
-- 26. LOANER HISTORY
-- ============================================================================
CREATE TABLE IF NOT EXISTS loaner_history (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    loaner_device_id INTEGER NOT NULL REFERENCES loaner_devices(id),
    ticket_device_id INTEGER NOT NULL REFERENCES ticket_devices(id),
    customer_id      INTEGER NOT NULL REFERENCES customers(id),
    loaned_at        TEXT NOT NULL DEFAULT (datetime('now')),
    returned_at      TEXT,
    condition_out    TEXT,
    condition_in     TEXT,
    notes            TEXT
);

CREATE INDEX IF NOT EXISTS idx_loaner_history_loaner_id ON loaner_history(loaner_device_id);
CREATE INDEX IF NOT EXISTS idx_loaner_history_customer  ON loaner_history(customer_id);

-- ============================================================================
-- 27. INVENTORY SERIALS
-- ============================================================================
CREATE TABLE IF NOT EXISTS inventory_serials (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    inventory_item_id INTEGER NOT NULL REFERENCES inventory_items(id),
    serial_number     TEXT NOT NULL,
    status            TEXT NOT NULL DEFAULT 'in_stock' CHECK (status IN ('in_stock', 'sold', 'returned', 'defective')),
    created_at        TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at        TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_inventory_serials_item_id ON inventory_serials(inventory_item_id);
CREATE INDEX IF NOT EXISTS idx_inventory_serials_serial  ON inventory_serials(serial_number);

-- ============================================================================
-- 28. INVENTORY GROUP PRICES
-- ============================================================================
CREATE TABLE IF NOT EXISTS inventory_group_prices (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    inventory_item_id INTEGER NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
    customer_group_id INTEGER NOT NULL REFERENCES customer_groups(id),
    price             REAL NOT NULL DEFAULT 0,
    UNIQUE(inventory_item_id, customer_group_id)
);

CREATE INDEX IF NOT EXISTS idx_inventory_group_prices_item_id ON inventory_group_prices(inventory_item_id);

-- ============================================================================
-- 29. STOCK MOVEMENTS
-- ============================================================================
CREATE TABLE IF NOT EXISTS stock_movements (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    inventory_item_id INTEGER NOT NULL REFERENCES inventory_items(id),
    type              TEXT NOT NULL,
    quantity          INTEGER NOT NULL DEFAULT 0,
    reference_type    TEXT,
    reference_id      INTEGER,
    notes             TEXT,
    user_id           INTEGER REFERENCES users(id),
    created_at        TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at        TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_stock_movements_item_id ON stock_movements(inventory_item_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_type    ON stock_movements(type);

-- ============================================================================
-- 30. PURCHASE ORDERS
-- ============================================================================
CREATE TABLE IF NOT EXISTS purchase_orders (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id      TEXT NOT NULL UNIQUE,
    supplier_id   INTEGER NOT NULL REFERENCES suppliers(id),
    status        TEXT NOT NULL DEFAULT 'draft',
    paid_status   TEXT NOT NULL DEFAULT 'unpaid',
    subtotal      REAL NOT NULL DEFAULT 0,
    tax           REAL NOT NULL DEFAULT 0,
    total         REAL NOT NULL DEFAULT 0,
    notes         TEXT,
    expected_date TEXT,
    received_date TEXT,
    created_by    INTEGER NOT NULL REFERENCES users(id),
    created_at    TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_purchase_orders_order_id    ON purchase_orders(order_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier_id ON purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_status      ON purchase_orders(status);

-- ============================================================================
-- 31. PURCHASE ORDER ITEMS
-- ============================================================================
CREATE TABLE IF NOT EXISTS purchase_order_items (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    purchase_order_id INTEGER NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    inventory_item_id INTEGER NOT NULL REFERENCES inventory_items(id),
    quantity_ordered  INTEGER NOT NULL DEFAULT 0,
    quantity_received INTEGER NOT NULL DEFAULT 0,
    cost_price        REAL NOT NULL DEFAULT 0,
    created_at        TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at        TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_po_items_order_id ON purchase_order_items(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_po_items_item_id  ON purchase_order_items(inventory_item_id);

-- ============================================================================
-- 32. INVOICE LINE ITEMS
-- ============================================================================
CREATE TABLE IF NOT EXISTS invoice_line_items (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    invoice_id        INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    inventory_item_id INTEGER REFERENCES inventory_items(id),
    description       TEXT NOT NULL DEFAULT '',
    quantity          INTEGER NOT NULL DEFAULT 1,
    unit_price        REAL NOT NULL DEFAULT 0,
    line_discount     REAL NOT NULL DEFAULT 0,
    tax_amount        REAL NOT NULL DEFAULT 0,
    tax_class_id      INTEGER REFERENCES tax_classes(id),
    total             REAL NOT NULL DEFAULT 0,
    notes             TEXT,
    created_at        TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at        TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_invoice_line_items_invoice_id ON invoice_line_items(invoice_id);

-- ============================================================================
-- 33. PAYMENTS
-- ============================================================================
CREATE TABLE IF NOT EXISTS payments (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    invoice_id     INTEGER NOT NULL REFERENCES invoices(id),
    amount         REAL NOT NULL DEFAULT 0,
    method         TEXT NOT NULL,
    method_detail  TEXT,
    transaction_id TEXT,
    notes          TEXT,
    user_id        INTEGER NOT NULL REFERENCES users(id),
    created_at     TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at     TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_payments_invoice_id ON payments(invoice_id);

-- ============================================================================
-- 34. LEADS
-- ============================================================================
CREATE TABLE IF NOT EXISTS leads (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id    TEXT NOT NULL UNIQUE,
    customer_id INTEGER REFERENCES customers(id),
    first_name  TEXT NOT NULL DEFAULT '',
    last_name   TEXT NOT NULL DEFAULT '',
    email       TEXT,
    phone       TEXT,
    zip_code    TEXT,
    address     TEXT,
    status      TEXT NOT NULL DEFAULT 'new',
    referred_by TEXT,
    assigned_to INTEGER REFERENCES users(id),
    source      TEXT,
    notes       TEXT,
    created_by  INTEGER REFERENCES users(id),
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_leads_order_id    ON leads(order_id);
CREATE INDEX IF NOT EXISTS idx_leads_customer_id ON leads(customer_id);
CREATE INDEX IF NOT EXISTS idx_leads_status      ON leads(status);
CREATE INDEX IF NOT EXISTS idx_leads_assigned_to ON leads(assigned_to);

-- ============================================================================
-- 35. LEAD DEVICES
-- ============================================================================
CREATE TABLE IF NOT EXISTS lead_devices (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    lead_id        INTEGER NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
    device_name    TEXT NOT NULL DEFAULT '',
    repair_type    TEXT,
    service_type   TEXT,
    service_id     INTEGER REFERENCES inventory_items(id),
    price          REAL NOT NULL DEFAULT 0,
    tax            REAL NOT NULL DEFAULT 0,
    problem        TEXT,
    customer_notes TEXT,
    security_code  TEXT,
    start_time     TEXT,
    end_time       TEXT
);

CREATE INDEX IF NOT EXISTS idx_lead_devices_lead_id ON lead_devices(lead_id);

-- ============================================================================
-- 36. APPOINTMENTS
-- ============================================================================
CREATE TABLE IF NOT EXISTS appointments (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    lead_id     INTEGER REFERENCES leads(id),
    customer_id INTEGER REFERENCES customers(id),
    title       TEXT NOT NULL DEFAULT '',
    start_time  TEXT NOT NULL,
    end_time    TEXT,
    assigned_to INTEGER REFERENCES users(id),
    status      TEXT NOT NULL DEFAULT 'scheduled',
    notes       TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_appointments_lead_id     ON appointments(lead_id);
CREATE INDEX IF NOT EXISTS idx_appointments_customer_id ON appointments(customer_id);
CREATE INDEX IF NOT EXISTS idx_appointments_start_time  ON appointments(start_time);
CREATE INDEX IF NOT EXISTS idx_appointments_assigned_to ON appointments(assigned_to);

-- ============================================================================
-- 37. ESTIMATE LINE ITEMS
-- ============================================================================
CREATE TABLE IF NOT EXISTS estimate_line_items (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    estimate_id       INTEGER NOT NULL REFERENCES estimates(id) ON DELETE CASCADE,
    inventory_item_id INTEGER REFERENCES inventory_items(id),
    description       TEXT NOT NULL DEFAULT '',
    quantity          INTEGER NOT NULL DEFAULT 1,
    unit_price        REAL NOT NULL DEFAULT 0,
    tax_amount        REAL NOT NULL DEFAULT 0,
    total             REAL NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_estimate_line_items_estimate_id ON estimate_line_items(estimate_id);

-- ============================================================================
-- 38. POS TRANSACTIONS
-- ============================================================================
CREATE TABLE IF NOT EXISTS pos_transactions (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    invoice_id     INTEGER REFERENCES invoices(id),
    customer_id    INTEGER REFERENCES customers(id),
    total          REAL NOT NULL DEFAULT 0,
    payment_method TEXT,
    user_id        INTEGER NOT NULL REFERENCES users(id),
    register_id    TEXT,
    created_at     TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at     TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_pos_transactions_invoice_id ON pos_transactions(invoice_id);
CREATE INDEX IF NOT EXISTS idx_pos_transactions_user_id    ON pos_transactions(user_id);

-- ============================================================================
-- 39. CASH REGISTER
-- ============================================================================
CREATE TABLE IF NOT EXISTS cash_register (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    type       TEXT NOT NULL CHECK (type IN ('cash_in', 'cash_out')),
    amount     REAL NOT NULL DEFAULT 0,
    reason     TEXT,
    user_id    INTEGER NOT NULL REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============================================================================
-- 40. SMS MESSAGES
-- ============================================================================
CREATE TABLE IF NOT EXISTS sms_messages (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    from_number TEXT,
    to_number   TEXT,
    conv_phone  TEXT,
    message     TEXT,
    status      TEXT NOT NULL DEFAULT 'pending',
    direction   TEXT NOT NULL DEFAULT 'outbound',
    error       TEXT,
    provider    TEXT,
    entity_type TEXT,
    entity_id   INTEGER,
    user_id     INTEGER REFERENCES users(id),
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_sms_messages_conv_phone   ON sms_messages(conv_phone);
CREATE INDEX IF NOT EXISTS idx_sms_messages_entity       ON sms_messages(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_sms_messages_status       ON sms_messages(status);
CREATE INDEX IF NOT EXISTS idx_sms_messages_direction    ON sms_messages(direction);
CREATE INDEX IF NOT EXISTS idx_sms_messages_created_at   ON sms_messages(created_at);

-- ============================================================================
-- 41. SMS TEMPLATES
-- ============================================================================
CREATE TABLE IF NOT EXISTS sms_templates (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL,
    content    TEXT NOT NULL,
    category   TEXT,
    is_active  INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============================================================================
-- 42. EMAIL MESSAGES
-- ============================================================================
CREATE TABLE IF NOT EXISTS email_messages (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    from_address TEXT,
    to_address   TEXT,
    subject      TEXT,
    body         TEXT,
    status       TEXT NOT NULL DEFAULT 'pending',
    entity_type  TEXT,
    entity_id    INTEGER,
    user_id      INTEGER REFERENCES users(id),
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_email_messages_entity ON email_messages(entity_type, entity_id);

-- ============================================================================
-- 43. SNIPPETS
-- ============================================================================
CREATE TABLE IF NOT EXISTS snippets (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    shortcode  TEXT NOT NULL UNIQUE,
    title      TEXT NOT NULL,
    content    TEXT NOT NULL,
    category   TEXT,
    created_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============================================================================
-- 44. NOTIFICATIONS
-- ============================================================================
CREATE TABLE IF NOT EXISTS notifications (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    type        TEXT NOT NULL,
    title       TEXT NOT NULL,
    message     TEXT,
    entity_type TEXT,
    entity_id   INTEGER,
    is_read     INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread ON notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_entity      ON notifications(entity_type, entity_id);

-- ============================================================================
-- 45. CLOCK ENTRIES
-- ============================================================================
CREATE TABLE IF NOT EXISTS clock_entries (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    clock_in    TEXT NOT NULL,
    clock_out   TEXT,
    total_hours REAL,
    notes       TEXT
);

CREATE INDEX IF NOT EXISTS idx_clock_entries_user_id ON clock_entries(user_id);

-- ============================================================================
-- 46. COMMISSIONS
-- ============================================================================
CREATE TABLE IF NOT EXISTS commissions (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id    INTEGER NOT NULL REFERENCES users(id),
    ticket_id  INTEGER REFERENCES tickets(id),
    invoice_id INTEGER REFERENCES invoices(id),
    amount     REAL NOT NULL DEFAULT 0,
    type       TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_commissions_user_id ON commissions(user_id);

-- ============================================================================
-- 47. EXPENSES
-- ============================================================================
CREATE TABLE IF NOT EXISTS expenses (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    category     TEXT,
    amount       REAL NOT NULL DEFAULT 0,
    description  TEXT,
    date         TEXT,
    receipt_path TEXT,
    user_id      INTEGER NOT NULL REFERENCES users(id),
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_expenses_user_id  ON expenses(user_id);
CREATE INDEX IF NOT EXISTS idx_expenses_date     ON expenses(date);
CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category);

-- ============================================================================
-- 48. AUTOMATIONS
-- ============================================================================
CREATE TABLE IF NOT EXISTS automations (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    name           TEXT NOT NULL,
    is_active      INTEGER NOT NULL DEFAULT 1,
    trigger_type   TEXT NOT NULL,
    trigger_config TEXT DEFAULT '{}',                          -- JSON
    action_type    TEXT NOT NULL,
    action_config  TEXT DEFAULT '{}',                          -- JSON
    sort_order     INTEGER NOT NULL DEFAULT 0,
    created_at     TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at     TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============================================================================
-- 49. CUSTOM FIELD DEFINITIONS
-- ============================================================================
CREATE TABLE IF NOT EXISTS custom_field_definitions (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type TEXT NOT NULL,
    field_name  TEXT NOT NULL,
    field_type  TEXT NOT NULL DEFAULT 'text',
    options     TEXT DEFAULT '[]',                             -- JSON
    is_required INTEGER NOT NULL DEFAULT 0,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(entity_type, field_name)
);

-- ============================================================================
-- 50. CUSTOM FIELD VALUES
-- ============================================================================
CREATE TABLE IF NOT EXISTS custom_field_values (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    definition_id INTEGER NOT NULL REFERENCES custom_field_definitions(id) ON DELETE CASCADE,
    entity_type   TEXT NOT NULL,
    entity_id     INTEGER NOT NULL,
    value         TEXT,
    UNIQUE(definition_id, entity_type, entity_id)
);

CREATE INDEX IF NOT EXISTS idx_custom_field_values_entity ON custom_field_values(entity_type, entity_id);

-- ============================================================================
-- 51. DEVICE OTPs
-- ============================================================================
CREATE TABLE IF NOT EXISTS device_otps (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    ticket_id        INTEGER NOT NULL REFERENCES tickets(id),
    ticket_device_id INTEGER NOT NULL REFERENCES ticket_devices(id),
    code             TEXT NOT NULL,
    phone            TEXT,
    is_verified      INTEGER NOT NULL DEFAULT 0,
    expires_at       TEXT NOT NULL,
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_device_otps_ticket_id ON device_otps(ticket_id);

-- ============================================================================
-- 52. USER PREFERENCES
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_preferences (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    key     TEXT NOT NULL,
    value   TEXT DEFAULT '{}',                                 -- JSON
    UNIQUE(user_id, key)
);

CREATE INDEX IF NOT EXISTS idx_user_preferences_user_id ON user_preferences(user_id);

-- ============================================================================
-- 53. IMPORT RUNS
-- ============================================================================
CREATE TABLE IF NOT EXISTS import_runs (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    source        TEXT NOT NULL,
    entity_type   TEXT NOT NULL,
    status        TEXT NOT NULL DEFAULT 'pending',
    total_records INTEGER NOT NULL DEFAULT 0,
    imported      INTEGER NOT NULL DEFAULT 0,
    skipped       INTEGER NOT NULL DEFAULT 0,
    errors        INTEGER NOT NULL DEFAULT 0,
    error_log     TEXT DEFAULT '[]',                           -- JSON
    started_at    TEXT,
    completed_at  TEXT
);

-- ============================================================================
-- 54. IMPORT ID MAP
-- ============================================================================
CREATE TABLE IF NOT EXISTS import_id_map (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    import_run_id INTEGER NOT NULL REFERENCES import_runs(id),
    entity_type   TEXT NOT NULL,
    source_id     TEXT NOT NULL,
    local_id      INTEGER NOT NULL,
    UNIQUE(import_run_id, entity_type, source_id)
);

CREATE INDEX IF NOT EXISTS idx_import_id_map_run_id ON import_id_map(import_run_id);

-- ============================================================================
-- 55. FULL-TEXT SEARCH: CUSTOMERS
-- ============================================================================
CREATE VIRTUAL TABLE IF NOT EXISTS customers_fts USING fts5(
    first_name,
    last_name,
    email,
    phone,
    mobile,
    organization,
    city,
    postcode,
    tags,
    content='customers',
    content_rowid='id'
);

-- FTS triggers for customers: keep FTS index in sync with source table
CREATE TRIGGER IF NOT EXISTS customers_fts_insert AFTER INSERT ON customers BEGIN
    INSERT INTO customers_fts(rowid, first_name, last_name, email, phone, mobile, organization, city, postcode, tags)
    VALUES (NEW.id, NEW.first_name, NEW.last_name, NEW.email, NEW.phone, NEW.mobile, NEW.organization, NEW.city, NEW.postcode, NEW.tags);
END;

CREATE TRIGGER IF NOT EXISTS customers_fts_delete BEFORE DELETE ON customers BEGIN
    INSERT INTO customers_fts(customers_fts, rowid, first_name, last_name, email, phone, mobile, organization, city, postcode, tags)
    VALUES ('delete', OLD.id, OLD.first_name, OLD.last_name, OLD.email, OLD.phone, OLD.mobile, OLD.organization, OLD.city, OLD.postcode, OLD.tags);
END;

CREATE TRIGGER IF NOT EXISTS customers_fts_update AFTER UPDATE ON customers BEGIN
    INSERT INTO customers_fts(customers_fts, rowid, first_name, last_name, email, phone, mobile, organization, city, postcode, tags)
    VALUES ('delete', OLD.id, OLD.first_name, OLD.last_name, OLD.email, OLD.phone, OLD.mobile, OLD.organization, OLD.city, OLD.postcode, OLD.tags);
    INSERT INTO customers_fts(rowid, first_name, last_name, email, phone, mobile, organization, city, postcode, tags)
    VALUES (NEW.id, NEW.first_name, NEW.last_name, NEW.email, NEW.phone, NEW.mobile, NEW.organization, NEW.city, NEW.postcode, NEW.tags);
END;

-- ============================================================================
-- 56. FULL-TEXT SEARCH: TICKETS
-- ============================================================================
CREATE VIRTUAL TABLE IF NOT EXISTS tickets_fts USING fts5(
    order_id,
    device_names,
    customer_name,
    notes_text,
    labels,
    content='tickets',
    content_rowid='id'
);

-- ============================================================================
-- END OF MIGRATION 001
-- ============================================================================
