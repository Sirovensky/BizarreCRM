package com.bizarreelectronics.crm.data.local.db

import android.util.Log
import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.bizarreelectronics.crm.data.local.db.converters.Converters
import com.bizarreelectronics.crm.data.local.db.dao.*
import com.bizarreelectronics.crm.data.local.db.entities.*
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
    ],
    version = 3,
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

    companion object {
        const val DATABASE_NAME = "bizarre_crm.db"

        /** Current schema version — must match the `version` in @Database above.
         *  Keep in sync when bumping. Used for logging only. */
        const val SCHEMA_VERSION = 3
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
