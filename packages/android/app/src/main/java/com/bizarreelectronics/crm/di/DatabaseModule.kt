package com.bizarreelectronics.crm.di

import android.content.Context
import androidx.room.Room
import com.bizarreelectronics.crm.data.local.db.BizarreDatabase
import com.bizarreelectronics.crm.data.local.db.dao.*
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): BizarreDatabase {
        return Room.databaseBuilder(
            context,
            BizarreDatabase::class.java,
            BizarreDatabase.DATABASE_NAME,
        )
            // WARNING: fallbackToDestructiveMigration silently deletes all local data
            // when the schema version changes without a matching Migration object.
            // This is acceptable during early development (local DB is a cache of server
            // data), but MUST be replaced with proper addMigrations() once the schema
            // stabilizes.  exportSchema is now true in BizarreDatabase so Room exports
            // JSON schemas that can be used to write incremental migrations.
            .fallbackToDestructiveMigration()
            .addMigrations(/* add Migration objects here as the schema evolves */)
            .build()
    }

    @Provides fun provideTicketDao(db: BizarreDatabase): TicketDao = db.ticketDao()
    @Provides fun provideCustomerDao(db: BizarreDatabase): CustomerDao = db.customerDao()
    @Provides fun provideInventoryDao(db: BizarreDatabase): InventoryDao = db.inventoryDao()
    @Provides fun provideInvoiceDao(db: BizarreDatabase): InvoiceDao = db.invoiceDao()
    @Provides fun provideSmsDao(db: BizarreDatabase): SmsDao = db.smsDao()
    @Provides fun provideCallLogDao(db: BizarreDatabase): CallLogDao = db.callLogDao()
    @Provides fun provideNotificationDao(db: BizarreDatabase): NotificationDao = db.notificationDao()
    @Provides fun provideSyncQueueDao(db: BizarreDatabase): SyncQueueDao = db.syncQueueDao()
    @Provides fun provideSyncMetadataDao(db: BizarreDatabase): SyncMetadataDao = db.syncMetadataDao()
    @Provides fun provideTicketStatusDao(db: BizarreDatabase): TicketStatusDao = db.ticketStatusDao()
    @Provides fun provideLeadDao(db: BizarreDatabase): LeadDao = db.leadDao()
    @Provides fun provideEstimateDao(db: BizarreDatabase): EstimateDao = db.estimateDao()
    @Provides fun provideExpenseDao(db: BizarreDatabase): ExpenseDao = db.expenseDao()
}
