package com.bizarreelectronics.crm.data.local.db

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.bizarreelectronics.crm.data.local.db.converters.Converters
import com.bizarreelectronics.crm.data.local.db.dao.*
import com.bizarreelectronics.crm.data.local.db.entities.*

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
    ],
    version = 1,
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

    companion object {
        const val DATABASE_NAME = "bizarre_crm.db"
    }
}
