package com.bizarreelectronics.crm.di

import android.content.Context
import android.util.Log
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.sqlite.db.SupportSQLiteDatabase
import com.bizarreelectronics.crm.data.local.db.BizarreDatabase
import com.bizarreelectronics.crm.data.local.db.Migrations
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

    private const val TAG = "DatabaseModule"

    /**
     * ---------------------------------------------------------------------------
     *  SQLCipher integration TODO — DO NOT DELETE
     * ---------------------------------------------------------------------------
     *
     *  Customer PII (phone numbers, addresses, tax IDs), ticket details, and
     *  invoice amounts are currently written to disk as **plaintext SQLite**.
     *  A rooted device or forensic extraction reveals every row.
     *
     *  To fix this properly:
     *
     *  1. Add to `app/build.gradle.kts`:
     *       implementation("net.zetetic:sqlcipher-android:4.6.1@aar")
     *       implementation("androidx.sqlite:sqlite-ktx:2.4.0")
     *
     *  2. Generate a passphrase on first launch, derived from an Android
     *     Keystore-backed AES key. Store the wrapped passphrase in
     *     EncryptedSharedPreferences (AuthPreferences already uses AES256-GCM
     *     so the infrastructure is in place). The passphrase must NEVER be
     *     hardcoded, stored in BuildConfig, or derived from a static string.
     *
     *  3. Wire SupportFactory into the Room builder:
     *       import net.sqlcipher.database.SupportFactory
     *       import net.sqlcipher.database.SQLiteDatabase
     *       SQLiteDatabase.loadLibs(context)
     *       val factory = SupportFactory(passphrase.toByteArray())
     *       Room.databaseBuilder(context, BizarreDatabase::class.java, DATABASE_NAME)
     *           .openHelperFactory(factory)
     *
     *  4. On logout, zero out the in-memory passphrase bytes and call
     *     [clearUserData] to wipe user data. Re-derive the passphrase on the
     *     next login.
     *
     *  5. When migrating an existing plaintext DB to SQLCipher, use
     *     `SQLiteDatabase.rawExecSQL("ATTACH DATABASE ... AS encrypted KEY '...'")`
     *     plus `SELECT sqlcipher_export('encrypted')` to copy rows across, then
     *     replace the on-disk file atomically.
     *
     *  Until steps 1-5 are complete, `android:allowBackup="false"` in the
     *  manifest is the ONLY thing stopping this data from leaving the device.
     *  Verify that flag every release.
     * ---------------------------------------------------------------------------
     */
    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): BizarreDatabase {
        // TODO(SQLCipher): derive passphrase from Android Keystore and wrap it in
        //  EncryptedSharedPreferences instead of constructing the builder unencrypted.
        //  See the banner comment above for the full integration plan.
        //
        // val passphrase: CharArray = SecureDatabasePassphrase.loadOrCreate(context)
        // val factory = net.sqlcipher.database.SupportFactory(
        //     net.sqlcipher.database.SQLiteDatabase.getBytes(passphrase)
        // )

        return Room.databaseBuilder(
            context,
            BizarreDatabase::class.java,
            BizarreDatabase.DATABASE_NAME,
        )
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
            // .openHelperFactory(factory) // TODO(SQLCipher): enable once passphrase derivation is wired
            .build()
            .also {
                Log.i(TAG, "Room database opened (version=${BizarreDatabase.SCHEMA_VERSION})")
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
