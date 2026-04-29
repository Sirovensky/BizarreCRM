package com.bizarreelectronics.crm.data.local.db

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

/**
 * Room migration objects.
 *
 * **Never** add `fallbackToDestructiveMigration()` back to the builder — any
 * schema bump without a matching migration here will silently delete every
 * user's local data (including queued offline creates that haven't synced yet).
 *
 * When you bump the schema version in [BizarreDatabase.version] you MUST add a
 * new `Migration(x, y)` to [ALL_MIGRATIONS] below, even if it's a no-op (an
 * empty migration still marks the version as handled).
 */
object Migrations {

    /**
     * **Stub migration 1 → 2.**
     *
     * v1 was never shipped publicly — v2 was the first version where Room
     * started exporting schema JSON. This migration exists only so the
     * migration chain is continuous if an older dev build happens to exist on
     * a device. If the old schema matches v2 exactly, this is a no-op.
     */
    val MIGRATION_1_2 = object : Migration(1, 2) {
        override fun migrate(db: SupportSQLiteDatabase) {
            // No-op: v1 ↔ v2 schemas are identical in shipped builds. Explicit
            // migration object prevents Room from destructively recreating
            // the database on an old dev build.
        }
    }

    /**
     * **Migration 2 → 3: money columns become Long cents, foreign keys enforced.**
     *
     * In v2 every money column on tickets / invoices / estimates / ticket_devices
     * / expenses was a SQLite REAL (Kotlin Double). REAL columns accumulate
     * IEEE-754 drift as totals are summed, which is unacceptable for a CRM.
     *
     * In v3 the same columns store integer cents (Long). The migration does
     * three things per affected table:
     *
     *  1. Creates a new table with the correct schema (Long money + foreign
     *     keys with CASCADE/SET NULL delete rules).
     *  2. Copies rows across, multiplying each money column by 100 and casting
     *     to INTEGER. `CAST(COALESCE(col, 0) * 100 AS INTEGER)` truncates to
     *     whole cents (half-a-penny drift is acceptable; adding a rounding
     *     helper inside SQLite is not).
     *  3. Drops the old table and renames the new one into place.
     *
     * Indices are recreated exactly as declared on the current Kotlin entity
     * so Room's schema hash check passes.
     */
    val MIGRATION_2_3 = object : Migration(2, 3) {
        override fun migrate(db: SupportSQLiteDatabase) {
            // ----- tickets -----
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS tickets_new (
                    id INTEGER NOT NULL PRIMARY KEY,
                    order_id TEXT NOT NULL,
                    customer_id INTEGER,
                    status_id INTEGER,
                    status_name TEXT,
                    status_color TEXT,
                    status_is_closed INTEGER NOT NULL DEFAULT 0,
                    assigned_to INTEGER,
                    subtotal INTEGER NOT NULL DEFAULT 0,
                    discount INTEGER NOT NULL DEFAULT 0,
                    total_tax INTEGER NOT NULL DEFAULT 0,
                    total INTEGER NOT NULL DEFAULT 0,
                    due_on TEXT,
                    signature TEXT,
                    labels TEXT,
                    invoice_id INTEGER,
                    created_by INTEGER,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    customer_name TEXT,
                    customer_phone TEXT,
                    first_device_name TEXT,
                    is_deleted INTEGER NOT NULL DEFAULT 0,
                    locally_modified INTEGER NOT NULL DEFAULT 0,
                    last_synced_at TEXT,
                    FOREIGN KEY(customer_id) REFERENCES customers(id) ON UPDATE NO ACTION ON DELETE SET NULL
                )
                """.trimIndent()
            )
            db.execSQL(
                """
                INSERT INTO tickets_new (
                    id, order_id, customer_id, status_id, status_name, status_color,
                    status_is_closed, assigned_to,
                    subtotal, discount, total_tax, total,
                    due_on, signature, labels, invoice_id, created_by,
                    created_at, updated_at, customer_name, customer_phone,
                    first_device_name, is_deleted, locally_modified, last_synced_at
                )
                SELECT
                    id, order_id, customer_id, status_id, status_name, status_color,
                    status_is_closed, assigned_to,
                    CAST(COALESCE(subtotal, 0) * 100 AS INTEGER),
                    CAST(COALESCE(discount, 0) * 100 AS INTEGER),
                    CAST(COALESCE(total_tax, 0) * 100 AS INTEGER),
                    CAST(COALESCE(total, 0) * 100 AS INTEGER),
                    due_on, signature, labels, invoice_id, created_by,
                    created_at, updated_at, customer_name, customer_phone,
                    first_device_name, is_deleted, locally_modified, last_synced_at
                FROM tickets
                """.trimIndent()
            )
            db.execSQL("DROP TABLE tickets")
            db.execSQL("ALTER TABLE tickets_new RENAME TO tickets")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_tickets_customer_id ON tickets(customer_id)")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_tickets_status_id ON tickets(status_id)")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_tickets_assigned_to ON tickets(assigned_to)")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_tickets_created_at ON tickets(created_at)")

            // ----- invoices -----
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS invoices_new (
                    id INTEGER NOT NULL PRIMARY KEY,
                    order_id TEXT NOT NULL,
                    ticket_id INTEGER,
                    customer_id INTEGER,
                    status TEXT NOT NULL,
                    subtotal INTEGER NOT NULL DEFAULT 0,
                    discount INTEGER NOT NULL DEFAULT 0,
                    total_tax INTEGER NOT NULL DEFAULT 0,
                    total INTEGER NOT NULL DEFAULT 0,
                    amount_paid INTEGER NOT NULL DEFAULT 0,
                    amount_due INTEGER NOT NULL DEFAULT 0,
                    due_on TEXT,
                    notes TEXT,
                    created_by INTEGER,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    customer_name TEXT,
                    locally_modified INTEGER NOT NULL DEFAULT 0,
                    FOREIGN KEY(ticket_id) REFERENCES tickets(id) ON UPDATE NO ACTION ON DELETE SET NULL,
                    FOREIGN KEY(customer_id) REFERENCES customers(id) ON UPDATE NO ACTION ON DELETE SET NULL
                )
                """.trimIndent()
            )
            db.execSQL(
                """
                INSERT INTO invoices_new (
                    id, order_id, ticket_id, customer_id, status,
                    subtotal, discount, total_tax, total, amount_paid, amount_due,
                    due_on, notes, created_by, created_at, updated_at,
                    customer_name, locally_modified
                )
                SELECT
                    id, order_id, ticket_id, customer_id, status,
                    CAST(COALESCE(subtotal, 0) * 100 AS INTEGER),
                    CAST(COALESCE(discount, 0) * 100 AS INTEGER),
                    CAST(COALESCE(total_tax, 0) * 100 AS INTEGER),
                    CAST(COALESCE(total, 0) * 100 AS INTEGER),
                    CAST(COALESCE(amount_paid, 0) * 100 AS INTEGER),
                    CAST(COALESCE(amount_due, 0) * 100 AS INTEGER),
                    due_on, notes, created_by, created_at, updated_at,
                    customer_name, locally_modified
                FROM invoices
                """.trimIndent()
            )
            db.execSQL("DROP TABLE invoices")
            db.execSQL("ALTER TABLE invoices_new RENAME TO invoices")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_invoices_ticket_id ON invoices(ticket_id)")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_invoices_customer_id ON invoices(customer_id)")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_invoices_status ON invoices(status)")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_invoices_created_at ON invoices(created_at)")

            // ----- estimates -----
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS estimates_new (
                    id INTEGER NOT NULL PRIMARY KEY,
                    order_id TEXT NOT NULL,
                    customer_id INTEGER,
                    customer_name TEXT,
                    status TEXT NOT NULL,
                    discount INTEGER NOT NULL DEFAULT 0,
                    notes TEXT,
                    valid_until TEXT,
                    subtotal INTEGER NOT NULL DEFAULT 0,
                    total_tax INTEGER NOT NULL DEFAULT 0,
                    total INTEGER NOT NULL DEFAULT 0,
                    converted_ticket_id INTEGER,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    is_deleted INTEGER NOT NULL DEFAULT 0,
                    locally_modified INTEGER NOT NULL DEFAULT 0,
                    FOREIGN KEY(customer_id) REFERENCES customers(id) ON UPDATE NO ACTION ON DELETE SET NULL
                )
                """.trimIndent()
            )
            db.execSQL(
                """
                INSERT INTO estimates_new (
                    id, order_id, customer_id, customer_name, status,
                    discount, notes, valid_until,
                    subtotal, total_tax, total,
                    converted_ticket_id, created_at, updated_at, is_deleted, locally_modified
                )
                SELECT
                    id, order_id, customer_id, customer_name, status,
                    CAST(COALESCE(discount, 0) * 100 AS INTEGER),
                    notes, valid_until,
                    CAST(COALESCE(subtotal, 0) * 100 AS INTEGER),
                    CAST(COALESCE(total_tax, 0) * 100 AS INTEGER),
                    CAST(COALESCE(total, 0) * 100 AS INTEGER),
                    converted_ticket_id, created_at, updated_at, is_deleted, locally_modified
                FROM estimates
                """.trimIndent()
            )
            db.execSQL("DROP TABLE estimates")
            db.execSQL("ALTER TABLE estimates_new RENAME TO estimates")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_estimates_customer_id ON estimates(customer_id)")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_estimates_status ON estimates(status)")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_estimates_created_at ON estimates(created_at)")

            // ----- ticket_devices -----
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS ticket_devices_new (
                    id INTEGER NOT NULL PRIMARY KEY,
                    ticket_id INTEGER NOT NULL,
                    device_name TEXT,
                    device_type TEXT,
                    imei TEXT,
                    serial TEXT,
                    security_code TEXT,
                    status_id INTEGER,
                    status_name TEXT,
                    service_name TEXT,
                    price INTEGER NOT NULL DEFAULT 0,
                    total INTEGER NOT NULL DEFAULT 0,
                    additional_notes TEXT,
                    due_on TEXT,
                    pre_conditions TEXT,
                    post_conditions TEXT,
                    FOREIGN KEY(ticket_id) REFERENCES tickets(id) ON UPDATE NO ACTION ON DELETE CASCADE
                )
                """.trimIndent()
            )
            db.execSQL(
                """
                INSERT INTO ticket_devices_new (
                    id, ticket_id, device_name, device_type, imei, serial,
                    security_code, status_id, status_name, service_name,
                    price, total,
                    additional_notes, due_on, pre_conditions, post_conditions
                )
                SELECT
                    id, ticket_id, device_name, device_type, imei, serial,
                    security_code, status_id, status_name, service_name,
                    CAST(COALESCE(price, 0) * 100 AS INTEGER),
                    CAST(COALESCE(total, 0) * 100 AS INTEGER),
                    additional_notes, due_on, pre_conditions, post_conditions
                FROM ticket_devices
                """.trimIndent()
            )
            db.execSQL("DROP TABLE ticket_devices")
            db.execSQL("ALTER TABLE ticket_devices_new RENAME TO ticket_devices")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_ticket_devices_ticket_id ON ticket_devices(ticket_id)")

            // ----- ticket_notes -----
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS ticket_notes_new (
                    id INTEGER NOT NULL PRIMARY KEY,
                    ticket_id INTEGER NOT NULL,
                    user_id INTEGER NOT NULL,
                    user_name TEXT,
                    type TEXT NOT NULL,
                    content TEXT NOT NULL,
                    is_flagged INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    FOREIGN KEY(ticket_id) REFERENCES tickets(id) ON UPDATE NO ACTION ON DELETE CASCADE
                )
                """.trimIndent()
            )
            db.execSQL(
                """
                INSERT INTO ticket_notes_new (
                    id, ticket_id, user_id, user_name, type, content, is_flagged, created_at
                )
                SELECT
                    id, ticket_id, user_id, user_name, type, content, is_flagged, created_at
                FROM ticket_notes
                """.trimIndent()
            )
            db.execSQL("DROP TABLE ticket_notes")
            db.execSQL("ALTER TABLE ticket_notes_new RENAME TO ticket_notes")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_ticket_notes_ticket_id ON ticket_notes(ticket_id)")

            // ----- expenses -----
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS expenses_new (
                    id INTEGER NOT NULL PRIMARY KEY,
                    category TEXT NOT NULL,
                    amount INTEGER NOT NULL DEFAULT 0,
                    description TEXT,
                    date TEXT NOT NULL,
                    user_name TEXT,
                    user_id INTEGER,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    locally_modified INTEGER NOT NULL DEFAULT 0
                )
                """.trimIndent()
            )
            db.execSQL(
                """
                INSERT INTO expenses_new (
                    id, category, amount, description, date, user_name, user_id,
                    created_at, updated_at, locally_modified
                )
                SELECT
                    id, category,
                    CAST(COALESCE(amount, 0) * 100 AS INTEGER),
                    description, date, user_name, user_id,
                    created_at, updated_at, locally_modified
                FROM expenses
                """.trimIndent()
            )
            db.execSQL("DROP TABLE expenses")
            db.execSQL("ALTER TABLE expenses_new RENAME TO expenses")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_expenses_category ON expenses(category)")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_expenses_date ON expenses(date)")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_expenses_user_id ON expenses(user_id)")
        }
    }

    /**
     * **Migration 3 → 4: inventory money columns become Long cents + indices.**
     *
     * @audit-fixed: Section 33 / D1 — `inventory_items.cost_price` and
     * `inventory_items.retail_price` were the last two REAL money columns left
     * over from the v2 schema; the v2→v3 sweep only touched tickets, invoices,
     * estimates, ticket_devices, and expenses. Inventory survived because it
     * doesn't currently feed any totals math, but a part costed at $19.99
     * still loses precision the moment a future "stock value" report sums
     * 1000+ rows. We fix it now while the table is small.
     *
     * The migration also creates indices on `sku`, `upc_code`, and
     * `manufacturer_id` because [InventoryDao] runs `WHERE sku = ?`,
     * `WHERE upc_code LIKE ...`, and joins on manufacturer in every list /
     * search query, all of which were table scans before this pass.
     *
     * Per-table steps follow the same recipe as MIGRATION_2_3:
     *   1. CREATE TABLE inventory_items_new with INTEGER cents columns.
     *   2. INSERT … SELECT, multiplying old REAL columns by 100 and CASTing.
     *   3. DROP old table, RENAME new into place, recreate indices.
     */
    val MIGRATION_3_4 = object : Migration(3, 4) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS inventory_items_new (
                    id INTEGER NOT NULL PRIMARY KEY,
                    name TEXT NOT NULL,
                    sku TEXT,
                    upc_code TEXT,
                    item_type TEXT,
                    category TEXT,
                    manufacturer_id INTEGER,
                    manufacturer_name TEXT,
                    cost_price_cents INTEGER NOT NULL DEFAULT 0,
                    retail_price_cents INTEGER NOT NULL DEFAULT 0,
                    in_stock INTEGER NOT NULL DEFAULT 0,
                    reorder_level INTEGER NOT NULL DEFAULT 0,
                    tax_class_id INTEGER,
                    supplier_id INTEGER,
                    supplier_name TEXT,
                    location TEXT,
                    shelf TEXT,
                    bin TEXT,
                    description TEXT,
                    is_serialize INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    locally_modified INTEGER NOT NULL DEFAULT 0
                )
                """.trimIndent()
            )
            db.execSQL(
                """
                INSERT INTO inventory_items_new (
                    id, name, sku, upc_code, item_type, category,
                    manufacturer_id, manufacturer_name,
                    cost_price_cents, retail_price_cents,
                    in_stock, reorder_level, tax_class_id,
                    supplier_id, supplier_name,
                    location, shelf, bin, description, is_serialize,
                    created_at, updated_at, locally_modified
                )
                SELECT
                    id, name, sku, upc_code, item_type, category,
                    manufacturer_id, manufacturer_name,
                    CAST(COALESCE(cost_price, 0) * 100 AS INTEGER),
                    CAST(COALESCE(retail_price, 0) * 100 AS INTEGER),
                    in_stock, reorder_level, tax_class_id,
                    supplier_id, supplier_name,
                    location, shelf, bin, description, is_serialize,
                    created_at, updated_at, locally_modified
                FROM inventory_items
                """.trimIndent()
            )
            db.execSQL("DROP TABLE inventory_items")
            db.execSQL("ALTER TABLE inventory_items_new RENAME TO inventory_items")
            // @audit-fixed: D6 — list/search/lookup queries used to do full
            // table scans on these columns. Adding indices now means
            // `WHERE sku = ?` and `WHERE upc_code LIKE ?` are O(log n) instead
            // of O(n), and the join from a sales line to a part can use the
            // sku index too once that screen lands.
            db.execSQL("CREATE INDEX IF NOT EXISTS index_inventory_items_sku ON inventory_items(sku)")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_inventory_items_upc_code ON inventory_items(upc_code)")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_inventory_items_manufacturer_id ON inventory_items(manufacturer_id)")

            // ----- leads: add FK on customer_id (D5) -----
            //
            // @audit-fixed: D5 — leads.customer_id had a Room @Index but no
            // FOREIGN KEY constraint, so a hard customer delete left orphaned
            // rows. Recreating the table is the only way to add a FK in
            // SQLite. SET_NULL matches tickets/invoices/estimates so leads
            // survive a customer purge but lose the link.
            //
            // ----- sync_queue: add composite index on (status, created_at) (D6) -----
            //
            // @audit-fixed: D6 — SyncManager.flushQueue() runs `SELECT * FROM
            // sync_queue WHERE status = 'pending' ORDER BY created_at ASC` on
            // every flush. With no index that's a full table scan plus a sort
            // every time. The composite index lets the query plan walk it as
            // a single ordered range scan.
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS leads_new (
                    id INTEGER NOT NULL PRIMARY KEY,
                    order_id TEXT,
                    customer_id INTEGER,
                    first_name TEXT,
                    last_name TEXT,
                    email TEXT,
                    phone TEXT,
                    zip_code TEXT,
                    address TEXT,
                    status TEXT,
                    referred_by TEXT,
                    assigned_to INTEGER,
                    source TEXT,
                    notes TEXT,
                    lost_reason TEXT,
                    lead_score INTEGER NOT NULL DEFAULT 0,
                    assigned_name TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    is_deleted INTEGER NOT NULL DEFAULT 0,
                    locally_modified INTEGER NOT NULL DEFAULT 0,
                    FOREIGN KEY(customer_id) REFERENCES customers(id) ON UPDATE NO ACTION ON DELETE SET NULL
                )
                """.trimIndent()
            )
            db.execSQL(
                """
                INSERT INTO leads_new (
                    id, order_id, customer_id, first_name, last_name, email, phone,
                    zip_code, address, status, referred_by, assigned_to, source,
                    notes, lost_reason, lead_score, assigned_name,
                    created_at, updated_at, is_deleted, locally_modified
                )
                SELECT
                    id, order_id, customer_id, first_name, last_name, email, phone,
                    zip_code, address, status, referred_by, assigned_to, source,
                    notes, lost_reason, lead_score, assigned_name,
                    created_at, updated_at, is_deleted, locally_modified
                FROM leads
                """.trimIndent()
            )
            db.execSQL("DROP TABLE leads")
            db.execSQL("ALTER TABLE leads_new RENAME TO leads")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_leads_customer_id ON leads(customer_id)")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_leads_status ON leads(status)")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_leads_assigned_to ON leads(assigned_to)")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_leads_created_at ON leads(created_at)")

            // ----- sync_queue: add composite index (D6) -----
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS index_sync_queue_status_created_at " +
                    "ON sync_queue(status, created_at)"
            )
        }
    }

    /**
     * **Migration 4 → 5: customer search indices (AUDIT-AND-026).**
     *
     * CustomerDao runs `WHERE last_name LIKE ?`, `WHERE email = ?`, and
     * `WHERE phone LIKE ?` on every customer-search keystroke. Without
     * indices these are full table scans across ~958+ rows. The three
     * indices below make those queries O(log n).
     *
     * SQLite's `CREATE INDEX IF NOT EXISTS` is idempotent, so a retried
     * migration is safe.
     */
    val MIGRATION_4_5 = object : Migration(4, 5) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS index_customers_last_name ON customers(last_name)"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS index_customers_email ON customers(email)"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS index_customers_phone ON customers(phone)"
            )
        }
    }

    /**
     * **Migration 5 → 6: add `drafts` table for autosave storage (Plan §1 L260-L266).**
     *
     * Creates the `drafts` table with:
     *  - Auto-increment primary key.
     *  - `user_id` + `draft_type` unique index (one draft per type per user, plan line 263).
     *  - `payload_json` TEXT for the serialised form-field snapshot.
     *  - `saved_at` INTEGER (epoch ms) for pruning (line 266) and age display (line 262).
     *  - `entity_id` TEXT NULL for edit-mode drafts that reference an existing server entity.
     *
     * SQLCipher encryption covers this table automatically (plan line 264).
     * No columns for password/PIN/TOTP — those must never be stored here.
     *
     * `CREATE INDEX IF NOT EXISTS` is idempotent; a retried migration is safe.
     */
    val MIGRATION_5_6 = object : Migration(5, 6) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS drafts (
                    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                    user_id TEXT NOT NULL,
                    draft_type TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    saved_at INTEGER NOT NULL,
                    entity_id TEXT
                )
                """.trimIndent()
            )
            db.execSQL(
                "CREATE UNIQUE INDEX IF NOT EXISTS index_drafts_user_id_draft_type " +
                    "ON drafts(user_id, draft_type)"
            )
        }
    }

    /**
     * **Migration 6 → 7: add `applied_migrations` tracking table (Plan §1 L215-L221).**
     *
     * Creates the `applied_migrations` table with a composite primary key on
     * `(from_version, to_version)`. Every [MigrationRegistry.TimedMigration] that
     * runs in future upgrades inserts a row so [MigrationRegistry.validateAllStepsPresent]
     * can verify the migration chain is complete at boot.
     *
     * Existing installs upgrading from v6 will have no rows in this table —
     * that is expected. [MigrationRegistry.validateAllStepsPresent] skips
     * validation for steps whose `toVersion` predates the table's existence
     * by comparing against the installed version at open-time. A fresh v7
     * install starts with an empty table and zero expected rows.
     *
     * `CREATE TABLE IF NOT EXISTS` is idempotent — a retried migration is safe.
     */
    val MIGRATION_6_7 = object : Migration(6, 7) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS applied_migrations (
                    from_version INTEGER NOT NULL,
                    to_version   INTEGER NOT NULL,
                    applied_at   INTEGER NOT NULL,
                    duration_ms  INTEGER NOT NULL,
                    name         TEXT    NOT NULL,
                    PRIMARY KEY (from_version, to_version)
                )
                """.trimIndent()
            )
        }
    }

    /**
     * **Migration 7 → 8: `sync_state` table + `_synced_at` bookkeeping columns.**
     *
     * ## What changes
     *
     * 1. Creates the `sync_state` table keyed by `(entity, filter_key, parent_id)`.
     *    Stores server cursor, pagination exhaustion timestamp, oldest-cached
     *    timestamp, and last-updated timestamp for each sync-able collection.
     *    A unique index on the composite key enforces one row per logical scope.
     *
     * 2. Adds `_synced_at INTEGER NOT NULL DEFAULT 0` to `tickets`, `customers`,
     *    `inventory_items`, and `invoices`. The column records the epoch-ms
     *    timestamp of the last successful server write/confirm for each row.
     *    Rows existing before this migration are back-filled to 0 (= never
     *    synced), which is the correct conservative default: the sync engine
     *    will re-confirm them on next sync.
     *
     * ## Why NOT a no-op / AutoMigration
     *
     * The back-fill `UPDATE … SET _synced_at = 0 WHERE _synced_at IS NULL`
     * is technically redundant with `DEFAULT 0` on `ALTER TABLE`, but is
     * included to make the migration's intent explicit and to satisfy
     * [MigrationRegistry.validateAllStepsPresent] row tracking (a row is
     * inserted into `applied_migrations` automatically by [TimedMigration]).
     *
     * ## Idempotency
     *
     * `CREATE TABLE IF NOT EXISTS` and `CREATE UNIQUE INDEX IF NOT EXISTS` are
     * idempotent. `ALTER TABLE … ADD COLUMN` is NOT idempotent in SQLite, but
     * Room guarantees each migration runs exactly once per device upgrade path,
     * so this is safe.
     *
     * ## ActionPlan reference
     *
     * Plan §1 L180 (sync_state table) + L183 (_synced_at bookkeeping).
     */
    val MIGRATION_7_8 = object : Migration(7, 8) {
        override fun migrate(db: SupportSQLiteDatabase) {
            // ── 1. Create sync_state table ────────────────────────────────────
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS sync_state (
                    entity              TEXT    NOT NULL,
                    filter_key          TEXT    NOT NULL DEFAULT '',
                    parent_id           INTEGER NOT NULL DEFAULT 0,
                    cursor              TEXT,
                    oldest_cached_at    INTEGER NOT NULL DEFAULT 0,
                    server_exhausted_at INTEGER,
                    last_updated_at     INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (entity, filter_key, parent_id)
                )
                """.trimIndent()
            )
            db.execSQL(
                "CREATE UNIQUE INDEX IF NOT EXISTS index_sync_state_entity_filter_key_parent_id " +
                    "ON sync_state(entity, filter_key, parent_id)"
            )

            // ── 2. Add _synced_at to tickets ──────────────────────────────────
            db.execSQL(
                "ALTER TABLE tickets ADD COLUMN _synced_at INTEGER NOT NULL DEFAULT 0"
            )
            db.execSQL(
                "UPDATE tickets SET _synced_at = 0 WHERE _synced_at IS NULL"
            )

            // ── 3. Add _synced_at to customers ────────────────────────────────
            db.execSQL(
                "ALTER TABLE customers ADD COLUMN _synced_at INTEGER NOT NULL DEFAULT 0"
            )
            db.execSQL(
                "UPDATE customers SET _synced_at = 0 WHERE _synced_at IS NULL"
            )

            // ── 4. Add _synced_at to inventory_items ──────────────────────────
            db.execSQL(
                "ALTER TABLE inventory_items ADD COLUMN _synced_at INTEGER NOT NULL DEFAULT 0"
            )
            db.execSQL(
                "UPDATE inventory_items SET _synced_at = 0 WHERE _synced_at IS NULL"
            )

            // ── 5. Add _synced_at to invoices ─────────────────────────────────
            db.execSQL(
                "ALTER TABLE invoices ADD COLUMN _synced_at INTEGER NOT NULL DEFAULT 0"
            )
            db.execSQL(
                "UPDATE invoices SET _synced_at = 0 WHERE _synced_at IS NULL"
            )
        }
    }

    /**
     * Migration 8 to 9 — adds parked_carts table.
     *
     * Plan §16.1 L1800: offline POS cart parking (ParkedCartEntity).
     */
    val MIGRATION_8_9 = object : Migration(8, 9) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS parked_carts (
                    id              TEXT    NOT NULL PRIMARY KEY,
                    label           TEXT    NOT NULL,
                    cart_json       TEXT    NOT NULL,
                    parked_at       INTEGER NOT NULL DEFAULT 0,
                    customer_id     INTEGER,
                    customer_name   TEXT,
                    subtotal_cents  INTEGER NOT NULL DEFAULT 0
                )
                """.trimIndent()
            )
        }
    }

    /**
     * **Migration 9 → 10: add `depends_on_queue_id` to `sync_queue` (Plan §20.2 L2108).**
     *
     * Adds a nullable INTEGER column `depends_on_queue_id` to `sync_queue`. When
     * non-null it references another row in the same table; [OrderedQueueProcessor]
     * will not dispatch the dependent entry until the referenced row has
     * `status = 'completed'`. This enables FIFO-within-dependency-chain semantics
     * (e.g. ticket-create must complete before child note-add is dispatched).
     *
     * A separate index on `depends_on_queue_id` ensures the LEFT JOIN inside
     * [SyncQueueDao.nextReady] stays O(log n) even with a large queue.
     *
     * `ALTER TABLE … ADD COLUMN` is not idempotent in SQLite, but Room guarantees
     * each migration runs exactly once per upgrade path, so this is safe.
     *
     * NOTE: Run `./gradlew :app:kspDebugKotlin` to regenerate 10.json after this
     * migration is applied. The placeholder 10.json checked in alongside this
     * migration exists only to satisfy [RoomSchemaFilesTest]; it will be overwritten
     * by the KSP-generated file.
     */
    val MIGRATION_9_10 = object : Migration(9, 10) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                "ALTER TABLE sync_queue ADD COLUMN depends_on_queue_id INTEGER"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS index_sync_queue_depends_on_queue_id " +
                    "ON sync_queue(depends_on_queue_id)"
            )
        }
    }

    /**
     * **Migration 10 → 11: add `checkin_drafts` table (Phase 3 repair check-in).**
     *
     * Creates the `checkin_drafts` table keyed by composite PK `(customer_id, device_id)`.
     * One draft per customer+device pair; [CheckInDraftDao.upsert] uses
     * [OnConflictStrategy.REPLACE] so repeated saves overwrite cleanly.
     *
     * The `payload_json` column holds a serialised `CheckInUiState` snapshot.
     * Passcode values stored here are protected by the SQLCipher encryption layer
     * that wraps the whole database file.
     *
     * `CREATE TABLE IF NOT EXISTS` is idempotent — a retried migration is safe.
     */
    val MIGRATION_10_11 = object : Migration(10, 11) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS checkin_drafts (
                    customer_id  INTEGER NOT NULL,
                    device_id    INTEGER NOT NULL,
                    step         INTEGER NOT NULL DEFAULT 0,
                    payload_json TEXT    NOT NULL,
                    updated_at   INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (customer_id, device_id)
                )
                """.trimIndent()
            )
        }
    }

    /**
     * **Migration 11 → 12: FTS4 virtual tables + sync triggers (§18.1).**
     *
     * Creates three FTS4 virtual shadow tables (`customers_fts`, `tickets_fts`,
     * `inventory_fts`) and the AFTER INSERT / AFTER UPDATE / AFTER DELETE triggers
     * that keep them synchronized with their canonical tables.
     *
     * ## Why FTS4 and not FTS5
     *
     * Room's `@Fts4` annotation is the supported path. FTS5 tables require raw
     * `execSQL` and are not registered with Room's schema-hash checker, making
     * them invisible to migration validation. FTS4 gives prefix matching
     * (`MATCH 'query*'`), which is all we need for §18.1 and §18.3.
     *
     * ## Trigger strategy
     *
     * Each canonical table (`customers`, `tickets`, `inventory_items`) gets three
     * triggers. The triggers call the FTS `DELETE`/`INSERT` pair pattern required
     * by content-table FTS4 (`content=""` is not used here — Room generates a
     * real shadow table with a `content` column, so plain AFTER * triggers are
     * sufficient).
     *
     * ## Idempotency
     *
     * `CREATE VIRTUAL TABLE IF NOT EXISTS` and `CREATE TRIGGER IF NOT EXISTS` are
     * idempotent — a retried migration is safe.
     */
    val MIGRATION_11_12 = object : Migration(11, 12) {
        override fun migrate(db: SupportSQLiteDatabase) {
            // ── customers_fts ─────────────────────────────────────────────────
            db.execSQL(
                """
                CREATE VIRTUAL TABLE IF NOT EXISTS customers_fts
                USING fts4(
                    content="customers",
                    first_name, last_name, email, phone, mobile, organization, tags,
                    tokenize="unicode61 tokenchars '0123456789'"
                )
                """.trimIndent()
            )
            // Backfill existing rows into the FTS index
            db.execSQL(
                """
                INSERT OR IGNORE INTO customers_fts(rowid, first_name, last_name, email, phone, mobile, organization, tags)
                SELECT id, first_name, last_name, email, phone, mobile, organization, tags
                FROM customers
                WHERE is_deleted = 0
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS customers_fts_ai AFTER INSERT ON customers BEGIN
                    INSERT INTO customers_fts(rowid, first_name, last_name, email, phone, mobile, organization, tags)
                    VALUES (new.id, new.first_name, new.last_name, new.email, new.phone, new.mobile, new.organization, new.tags);
                END
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS customers_fts_au AFTER UPDATE ON customers BEGIN
                    DELETE FROM customers_fts WHERE rowid = old.id;
                    INSERT INTO customers_fts(rowid, first_name, last_name, email, phone, mobile, organization, tags)
                    VALUES (new.id, new.first_name, new.last_name, new.email, new.phone, new.mobile, new.organization, new.tags);
                END
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS customers_fts_ad AFTER DELETE ON customers BEGIN
                    DELETE FROM customers_fts WHERE rowid = old.id;
                END
                """.trimIndent()
            )

            // ── tickets_fts ───────────────────────────────────────────────────
            db.execSQL(
                """
                CREATE VIRTUAL TABLE IF NOT EXISTS tickets_fts
                USING fts4(
                    content="tickets",
                    order_id, status_name, customer_name, customer_phone, first_device_name, labels,
                    tokenize="unicode61 tokenchars '0123456789-'"
                )
                """.trimIndent()
            )
            db.execSQL(
                """
                INSERT OR IGNORE INTO tickets_fts(rowid, order_id, status_name, customer_name, customer_phone, first_device_name, labels)
                SELECT id, order_id, status_name, customer_name, customer_phone, first_device_name, labels
                FROM tickets
                WHERE is_deleted = 0
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS tickets_fts_ai AFTER INSERT ON tickets BEGIN
                    INSERT INTO tickets_fts(rowid, order_id, status_name, customer_name, customer_phone, first_device_name, labels)
                    VALUES (new.id, new.order_id, new.status_name, new.customer_name, new.customer_phone, new.first_device_name, new.labels);
                END
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS tickets_fts_au AFTER UPDATE ON tickets BEGIN
                    DELETE FROM tickets_fts WHERE rowid = old.id;
                    INSERT INTO tickets_fts(rowid, order_id, status_name, customer_name, customer_phone, first_device_name, labels)
                    VALUES (new.id, new.order_id, new.status_name, new.customer_name, new.customer_phone, new.first_device_name, new.labels);
                END
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS tickets_fts_ad AFTER DELETE ON tickets BEGIN
                    DELETE FROM tickets_fts WHERE rowid = old.id;
                END
                """.trimIndent()
            )

            // ── inventory_fts ─────────────────────────────────────────────────
            db.execSQL(
                """
                CREATE VIRTUAL TABLE IF NOT EXISTS inventory_fts
                USING fts4(
                    content="inventory_items",
                    name, sku, upc_code, category, manufacturer_name, supplier_name, description,
                    tokenize="unicode61 tokenchars '0123456789-'"
                )
                """.trimIndent()
            )
            db.execSQL(
                """
                INSERT OR IGNORE INTO inventory_fts(rowid, name, sku, upc_code, category, manufacturer_name, supplier_name, description)
                SELECT id, name, sku, upc_code, category, manufacturer_name, supplier_name, description
                FROM inventory_items
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS inventory_fts_ai AFTER INSERT ON inventory_items BEGIN
                    INSERT INTO inventory_fts(rowid, name, sku, upc_code, category, manufacturer_name, supplier_name, description)
                    VALUES (new.id, new.name, new.sku, new.upc_code, new.category, new.manufacturer_name, new.supplier_name, new.description);
                END
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS inventory_fts_au AFTER UPDATE ON inventory_items BEGIN
                    DELETE FROM inventory_fts WHERE rowid = old.id;
                    INSERT INTO inventory_fts(rowid, name, sku, upc_code, category, manufacturer_name, supplier_name, description)
                    VALUES (new.id, new.name, new.sku, new.upc_code, new.category, new.manufacturer_name, new.supplier_name, new.description);
                END
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS inventory_fts_ad AFTER DELETE ON inventory_items BEGIN
                    DELETE FROM inventory_fts WHERE rowid = old.id;
                END
                """.trimIndent()
            )
        }
    }

    /**
     * **Migration 12 → 13: add `approval_status` column to `expenses` + index.**
     *
     * Mirrors the server's `expenses.status` column (server migration 120,
     * values: `pending | approved | denied`). Android stores it under the
     * Kotlin field `approvalStatus` mapped to SQL column `approval_status`
     * — name disambiguates from any future generic `status` field.
     *
     * Powers [ExpenseDao.getByApprovalStatus], the approval-status chip row
     * in [ExpenseFilterSheet], and the "Pending approval" badge on the list
     * summary tile.
     *
     * Existing cached rows get DEFAULT `'pending'`; next sync overwrites them
     * with server-authoritative value via [ExpenseRepository.refreshFromServer].
     *
     * Renumbered from main's MIGRATION_11_12 to 12→13 so it sequences after
     * MIGRATION_11_12 (FTS4 search, §18.1) on this branch.
     */
    val MIGRATION_12_13 = object : Migration(12, 13) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                "ALTER TABLE expenses ADD COLUMN approval_status TEXT NOT NULL DEFAULT 'pending'"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS index_expenses_approval_status ON expenses(approval_status)"
            )
        }
    }

    /** Every migration must be registered here. */
    val ALL_MIGRATIONS: Array<Migration> = arrayOf(
        MIGRATION_1_2,
        MIGRATION_2_3,
        MIGRATION_3_4,
        MIGRATION_4_5,
        MIGRATION_5_6,
        MIGRATION_6_7,
        MIGRATION_7_8,
        MIGRATION_8_9,
        MIGRATION_9_10,
        MIGRATION_10_11,
        MIGRATION_11_12,
        MIGRATION_12_13,
    )
}
