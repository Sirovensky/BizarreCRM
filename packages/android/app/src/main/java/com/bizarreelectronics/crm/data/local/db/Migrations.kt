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

    /** Every migration must be registered here. */
    val ALL_MIGRATIONS: Array<Migration> = arrayOf(
        MIGRATION_1_2,
        MIGRATION_2_3,
    )
}
