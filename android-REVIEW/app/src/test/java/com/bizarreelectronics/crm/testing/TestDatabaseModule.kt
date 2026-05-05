package com.bizarreelectronics.crm.testing

import android.content.Context
import androidx.room.Room
import com.bizarreelectronics.crm.data.local.db.BizarreDatabase
import com.bizarreelectronics.crm.data.local.db.dao.*
import com.bizarreelectronics.crm.data.local.draft.DraftDao
import com.bizarreelectronics.crm.di.DatabaseModule
import dagger.Module
import dagger.Provides
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dagger.hilt.testing.TestInstallIn
import javax.inject.Singleton

/**
 * TestDatabaseModule — replaces [DatabaseModule] in unit tests.
 *
 * Provides an unencrypted in-memory [BizarreDatabase] built with
 * `Room.inMemoryDatabaseBuilder`. This avoids Android Keystore / SQLCipher
 * keying, DatabaseGuard version checks, and PlaintextToEncryptedMigrator, all
 * of which require a real device context unavailable in JVM unit tests.
 *
 * The in-memory database is destroyed automatically when the test process exits.
 * Each `@HiltAndroidTest`-annotated test class gets a fresh singleton because
 * Hilt tears down the component between tests when using [HiltAndroidRule].
 *
 * Plan ref: ActionPlan §1.6 line 223.
 */
@Module
@TestInstallIn(
    components = [SingletonComponent::class],
    replaces = [DatabaseModule::class],
)
object TestDatabaseModule {

    @Provides
    @Singleton
    fun provideInMemoryDatabase(
        @ApplicationContext context: Context,
    ): BizarreDatabase =
        Room.inMemoryDatabaseBuilder(context, BizarreDatabase::class.java)
            .allowMainThreadQueries()
            .build()

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
    @Provides fun provideDraftDao(db: BizarreDatabase): DraftDao = db.draftDao()
    @Provides fun provideAppliedMigrationDao(db: BizarreDatabase): AppliedMigrationDao = db.appliedMigrationDao()
}
