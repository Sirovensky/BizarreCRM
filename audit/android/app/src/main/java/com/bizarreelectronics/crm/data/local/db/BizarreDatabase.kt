package com.bizarreelectronics.crm.data.local.db

import android.util.Log
import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.bizarreelectronics.crm.data.local.db.converters.Converters
import com.bizarreelectronics.crm.data.local.db.dao.*
import com.bizarreelectronics.crm.data.local.db.entities.*
import com.bizarreelectronics.crm.data.local.db.dao.CheckInDraftDao
import com.bizarreelectronics.crm.data.local.db.dao.ParkedCartDao
import com.bizarreelectronics.crm.data.local.db.entities.CheckInDraftEntity
import com.bizarreelectronics.crm.data.local.db.entities.ParkedCartEntity
import com.bizarreelectronics.crm.data.local.draft.DraftDao
import com.bizarreelectronics.crm.data.local.draft.DraftEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Room database definition for Bizarre Electronics CRM.
 *
 * ## Migration convention (ActionPlan §1 L215)
 *
 * All schema changes MUST be registered in [MigrationRegistry]. Choose the
 * right migration type:
 *
 * - **@AutoMigration** — for purely additive / shape-only changes with no data
 *   transformation. Declare the `@AutoMigration(from = X, to = Y)` annotation
 *   on this class and add a corresponding [MigrationRegistry.Entry]. Room
 *   generates the DDL automatically; no manual SQL is needed.
 * - **Manual [Migration]** — required whenever rows must be back-filled, column
 *   types change (e.g. REAL → INTEGER cents), foreign keys are added, or any
 *   data transformation is necessary. Add a `MIGRATION_N_(N+1)` object in
 *   [Migrations] with full KDoc explaining *why* the change is needed and
 *   *what data transform* occurs.
 *
 * Rule of thumb: if the diff to the schema JSON only adds a new table or adds
 * a nullable column, `@AutoMigration` is fine. If anything is renamed, altered
 * in type, or requires copying data between tables, use a manual migration.
 *
 * ## Version bump checklist
 *
 * 1. Bump `version` here and [SCHEMA_VERSION] below in lockstep.
 * 2. Add `MIGRATION_N_(N+1)` to [Migrations].
 * 3. Add an [MigrationRegistry.Entry] to [MigrationRegistry.ALL_ENTRIES].
 * 4. Update [com.bizarreelectronics.crm.data.local.db.RoomSchemaFilesTest] with
 *    the new JSON filename.
 * 5. Run `./gradlew :app:kspDebugKotlin` to export the schema JSON.
 */
@Database(
    entities = [
        TicketEntity::class,
        TicketDeviceEntity::class,
        TicketNoteEntity::class,
        TicketStatusEntity::class,
        CustomerEntity::class,
        InventoryItemEntity::class,
        InvoiceEntity::class,
        SmsMessageEntity::class,
        CallLogEntity::class,
        NotificationEntity::class,
        SyncQueueEntity::class,
        SyncMetadataEntity::class,
        LeadEntity::class,
        EstimateEntity::class,
        ExpenseEntity::class,
        DraftEntity::class,
        AppliedMigrationEntity::class,
        SyncStateEntity::class,
        ParkedCartEntity::class,
        CheckInDraftEntity::class,
        CustomerFtsEntity::class,
        TicketFtsEntity::class,
        InventoryFtsEntity::class,
    ],
    // @audit-fixed: Section 33 / D1 — bumped from 3 to 4 to convert
    // `inventory_items.cost_price` / `retail_price` from REAL → INTEGER cents
    // and to add the missing indices on sku/upc_code/manufacturer_id.
    //
    // AUD-20260414-L1: 3.json never made it into git when v3 shipped; the
    // gap is documented in
    // `app/schemas/com.bizarreelectronics.crm.data.local.db.BizarreDatabase/README.md`
    // and guarded by RoomSchemaFilesTest so we do not lose any further
    // schema exports.
    //
    // AUDIT-AND-026: bumped from 4 to 5 to add indices on customers.last_name,
    // customers.email, and customers.phone (search query optimisation).
    //
    // Plan §1 L260-266: bumped from 5 to 6 to add the `drafts` table for
    // autosave storage (DraftEntity + unique index on user_id+draft_type).
    //
    // Plan §1 L215-L221: bumped from 6 to 7 to add the `applied_migrations`
    // tracking table (AppliedMigrationEntity) for migration discipline.
    //
    // Plan §1 L180+L183: bumped from 7 to 8 to add `sync_state` table and
    // `_synced_at` bookkeeping columns on tickets/customers/inventory_items/invoices.
    // Plan �16.1 L1800: bumped from 8 to 9 to add parked_carts table.
    // Plan §20.2 L2108: bumped from 9 to 10 to add depends_on_queue_id to sync_queue.
    // Phase 3 check-in: bumped from 10 to 11 to add checkin_drafts table.
    // §18.1 search FTS: bumped from 11 to 12 to add FTS4 virtual tables
    // (customers_fts, tickets_fts, inventory_fts) + AFTER INSERT/UPDATE/DELETE triggers.
    // §11.1 Filters: bumped from 12 to 13 to add expenses.approval_status column
    // (mirrors server migration 120's `status` column, renamed locally for clarity).
    version = 13,
    exportSchema = true,
)
@TypeConverters(Converters::class)
abstract class BizarreDatabase : RoomDatabase() {

    abstract fun ticketDao(): TicketDao
    abstract fun customerDao(): CustomerDao
    abstract fun inventoryDao(): InventoryDao
    abstract fun invoiceDao(): InvoiceDao
    abstract fun smsDao(): SmsDao
    abstract fun callLogDao(): CallLogDao
    abstract fun notificationDao(): NotificationDao
    abstract fun syncQueueDao(): SyncQueueDao
    abstract fun syncMetadataDao(): SyncMetadataDao
    abstract fun ticketStatusDao(): TicketStatusDao
    abstract fun leadDao(): LeadDao
    abstract fun estimateDao(): EstimateDao
    abstract fun expenseDao(): ExpenseDao
    abstract fun draftDao(): DraftDao
    abstract fun appliedMigrationDao(): AppliedMigrationDao
    abstract fun syncStateDao(): SyncStateDao
    abstract fun parkedCartDao(): ParkedCartDao
    abstract fun checkInDraftDao(): CheckInDraftDao

    // §18.1 — FTS4 search DAOs
    abstract fun customerFtsDao(): CustomerFtsDao
    abstract fun ticketFtsDao(): TicketFtsDao
    abstract fun inventoryFtsDao(): InventoryFtsDao

    companion object {
        const val DATABASE_NAME = "bizarre_crm.db"

        /**
         * Current schema version — must match the `version` in @Database above.
         * Keep in sync when bumping.
         *
         * Used by [DatabaseGuard.checkForwardOnly] (downgrade protection) and
         * [MigrationRegistry.validateAllStepsPresent] (gap detection) in addition
         * to Room's internal version tracking.
         */
        const val SCHEMA_VERSION = 13
    }
}

/**
 * Wipe every row from every table. Called from [com.bizarreelectronics.crm.ui.screens.settings.SettingsScreen]
 * on logout so a second user on the same device cannot see the first user's
 * cached customers, tickets, invoices, SMS, or call history.
 *
 * This does NOT delete the database file — the schema (and, once SQLCipher is
 * wired, the encryption key) is preserved for the next login. Room's
 * [RoomDatabase.clearAllTables] runs in a transaction so either every table is
 * wiped or none are.
 */
suspend fun BizarreDatabase.clearUserData() = withContext(Dispatchers.IO) {
    clearAllTables()
    Log.i("BizarreDatabase", "clearAllTables() complete — local cache wiped after logout")
}
