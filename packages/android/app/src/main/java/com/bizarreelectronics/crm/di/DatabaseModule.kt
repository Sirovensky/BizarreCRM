package com.bizarreelectronics.crm.di

import android.content.Context
import android.util.Log
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.sqlite.db.SupportSQLiteDatabase
import com.bizarreelectronics.crm.data.local.db.BizarreDatabase
import com.bizarreelectronics.crm.data.local.db.Migrations
import com.bizarreelectronics.crm.data.local.db.dao.*
import com.bizarreelectronics.crm.data.local.prefs.DatabasePassphrase
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import net.zetetic.database.sqlcipher.SupportOpenHelperFactory
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    private const val TAG = "DatabaseModule"

    /**
     * Provides the Room database with SQLCipher-encrypted storage.
     *
     * Customer PII (phone numbers, addresses, tax IDs), ticket details, and
     * invoice amounts are encrypted at rest using a per-install random 32-byte
     * passphrase stored in [DatabasePassphrase] (which is itself backed by
     * EncryptedSharedPreferences with an Android Keystore master key). A
     * rooted device or forensic dump sees ciphertext, not plaintext rows.
     *
     * NOTE ON UPGRADE: existing unencrypted DBs from a pre-SQLCipher install
     * cannot be read with a passphrase. [Migrations.ALL_MIGRATIONS] does not
     * currently include a rekey/export step, so installs upgrading from a
     * previous build will crash on DB open with "file is not a database".
     * Follow-up work: either bump the schema version and run
     * sqlcipher_export() to copy the plaintext DB into an encrypted one, or
     * ship a one-shot migrator that wipes the old file and forces a full
     * re-sync from the server. Until then, Room's .fallbackToDestructiveMigration
     * is deliberately still NOT called (see note below), so the crash is
     * loud rather than silent.
     */
    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): BizarreDatabase {
        val passphrase: CharArray = DatabasePassphrase.loadOrCreate(context)
        val passphraseBytes = String(passphrase).toByteArray(Charsets.UTF_8)
        val factory = SupportOpenHelperFactory(passphraseBytes)

        return Room.databaseBuilder(
            context,
            BizarreDatabase::class.java,
            BizarreDatabase.DATABASE_NAME,
        )
            .openHelperFactory(factory)
            // NOTE: fallbackToDestructiveMigration() is deliberately NOT called.
            // Any schema bump MUST have a matching Migration object in
            // [Migrations.ALL_MIGRATIONS], otherwise the app will hard-fail on
            // first launch after upgrade instead of silently deleting queued
            // offline changes. If a migration throws, Room surfaces an
            // IllegalStateException which we WANT — a crash is recoverable,
            // silent data loss is not.
            .addMigrations(*Migrations.ALL_MIGRATIONS)
            // Enable SQLite foreign key enforcement on every connection.
            // Without this, our @ForeignKey annotations are decorative only.
            .addCallback(object : RoomDatabase.Callback() {
                override fun onOpen(db: SupportSQLiteDatabase) {
                    super.onOpen(db)
                    db.setForeignKeyConstraintsEnabled(true)
                    Log.d(TAG, "Foreign key enforcement enabled on DB connection")
                }

                override fun onCreate(db: SupportSQLiteDatabase) {
                    super.onCreate(db)
                    Log.i(TAG, "Room database created at version ${BizarreDatabase.SCHEMA_VERSION}")
                }
            })
            .build()
            .also {
                Log.i(TAG, "Room database opened (version=${BizarreDatabase.SCHEMA_VERSION}, encrypted=true)")
            }
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
