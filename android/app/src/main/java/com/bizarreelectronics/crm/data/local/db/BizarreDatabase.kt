package com.bizarreelectronics.crm.data.local.db

import android.util.Log
import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.bizarreelectronics.crm.data.local.db.converters.Converters
import com.bizarreelectronics.crm.data.local.db.dao.*
import com.bizarreelectronics.crm.data.local.db.entities.*
import com.bizarreelectronics.crm.data.local.draft.DraftDao
import com.bizarreelectronics.crm.data.local.draft.DraftEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

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
    version = 6,
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

    companion object {
        const val DATABASE_NAME = "bizarre_crm.db"

        /** Current schema version — must match the `version` in @Database above.
         *  Keep in sync when bumping. Used for logging only. */
        const val SCHEMA_VERSION = 6
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
