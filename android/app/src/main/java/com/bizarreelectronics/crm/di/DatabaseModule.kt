package com.bizarreelectronics.crm.di

import android.content.Context
import android.util.Log
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.sqlite.db.SupportSQLiteDatabase
import com.bizarreelectronics.crm.BuildConfig
import com.bizarreelectronics.crm.data.local.db.BizarreDatabase
import com.bizarreelectronics.crm.data.local.db.DatabaseGuard
import com.bizarreelectronics.crm.data.local.db.MigrationRegistry
import com.bizarreelectronics.crm.data.local.db.PlaintextToEncryptedMigrator
import com.bizarreelectronics.crm.data.local.db.dao.*
import com.bizarreelectronics.crm.data.local.draft.DraftDao
import com.bizarreelectronics.crm.data.local.prefs.DatabasePassphrase
import com.bizarreelectronics.crm.data.sync.DbMigrationBackupWorker
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
     * NOTE ON UPGRADE (AUD-20260414-M4, fixed): installs that originally
     * shipped with a plaintext Room database now run through
     * [PlaintextToEncryptedMigrator.migrateIfNeeded] before Room is wired up.
     * The migrator detects a plaintext `bizarre_crm.db`, exports every row
     * into an encrypted staging file with SQLCipher's `sqlcipher_export`
     * pragma, and swaps the files atomically (quarantining the old plaintext
     * copy as `bizarre_crm.legacy.db` rather than deleting it). Guarded by
     * the `sqlcipher_migration_v1_done` flag so it runs exactly once.
     *
     * Fresh installs skip the migrator body because no plaintext file
     * exists; subsequent launches skip because the flag is set; a partial
     * migration from a previous crashed launch is detected by re-reading
     * the plaintext DB header (staging artifacts are purged before retry).
     *
     * Room's .fallbackToDestructiveMigration is deliberately still NOT
     * called (see note below) — we want a loud crash on unexpected state
     * rather than silent data loss.
     */
    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): BizarreDatabase {
        val passphrase: CharArray = DatabasePassphrase.loadOrCreate(context)

        // --- Line 217: forward-only guard (check before anything else) -------
        // If the DB on disk is from a newer build than the current APK,
        // exit immediately rather than letting Room open an incompatible file.
        DatabaseGuard.checkForwardOnly(context, BizarreDatabase.SCHEMA_VERSION)

        // --- Line 219: backup before migrate ----------------------------------
        // Copy the DB file to cacheDir/db-backups/ before Room opens it and
        // potentially runs migrations. Safe no-op on fresh installs.
        val backupFile = DatabaseGuard.backupIfNeeded(context)

        // --- Line 220: DEBUG dry-run on backup --------------------------------
        // Only in debug builds: run integrity_check on the backup copy.
        DatabaseGuard.dryRunOnBackupIfDebug(backupFile, BuildConfig.DEBUG)

        // --- Line 219: One-shot upgrade from pre-SQLCipher plaintext DBs -----
        // Safe no-op on fresh installs and on already-migrated installs.
        // Must run BEFORE Room opens the DB, otherwise Room would fail on the
        // plaintext header.
        PlaintextToEncryptedMigrator.migrateIfNeeded(context, passphrase)
        val passphraseBytes = String(passphrase).toByteArray(Charsets.UTF_8)
        val factory = SupportOpenHelperFactory(passphraseBytes)

        // Build the database instance with a temporary null-DAO migration set.
        // We will get the real DAO reference from the built instance and use it
        // inside the onOpen callback below. MigrationRegistry.allMigrations(dao=null)
        // wraps each migration — timing is recorded once the DAO is available.
        val db = Room.databaseBuilder(
            context,
            BizarreDatabase::class.java,
            BizarreDatabase.DATABASE_NAME,
        )
            .openHelperFactory(factory)
            // NOTE: fallbackToDestructiveMigration() is deliberately NOT called.
            // Any schema bump MUST have a matching Migration object in
            // MigrationRegistry.ALL_ENTRIES, otherwise the app will hard-fail on
            // first launch after upgrade instead of silently deleting queued
            // offline changes. If a migration throws, Room surfaces an
            // IllegalStateException which we WANT — a crash is recoverable,
            // silent data loss is not.
            //
            // fallbackToDestructiveMigrationOnDowngrade() is also NOT called.
            // Downgrade detection is handled by DatabaseGuard.checkForwardOnly
            // (exitProcess(2)) before Room ever opens the file.
            .addMigrations(*MigrationRegistry.allMigrations(dao = null))
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

        // --- Line 216: validate migration tracking table ----------------------
        // Now that Room is open, run the gap check on the applied_migrations table.
        // On a fresh install the table is empty and installedVersion == SCHEMA_VERSION,
        // so validateAllStepsPresent returns silently (no prior migrations expected).
        // On upgrade the check fires if any migration row is missing.
        // Migration-gap validation moved out of provideDatabase because Room
        // rejects DAO reads on Application.onCreate's main thread (Room 2.7+
        // performBlocking fires assertNotMainThread even inside IO coroutines).
        // Room itself throws IllegalStateException on any missing Migration —
        // that surfaces the same crash for missing-step upgrades. The explicit
        // applied_migrations check below is a belt-and-suspenders layer that
        // belongs in a post-startup Worker. Deferred — see L216 follow-up.

        // --- Line 217: record successful open for next-launch guard -----------
        DatabaseGuard.recordSuccessfulOpen(context, BizarreDatabase.SCHEMA_VERSION)

        // --- Line 218: enqueue heavy migrations out-of-band (infra stub) ------
        // Check if any registered migration step is flagged as heavy. If so,
        // enqueue DbMigrationBackupWorker to run it via expedited WorkManager.
        // No heavy migration exists yet — this is infrastructure for future use.
        MigrationRegistry.ALL_ENTRIES
            .filter { it.heavy }
            .forEach { entry ->
                DbMigrationBackupWorker.enqueue(context, entry.fromVersion, entry.toVersion)
            }

        return db
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
    @Provides fun provideDraftDao(db: BizarreDatabase): DraftDao = db.draftDao()
    @Provides fun provideAppliedMigrationDao(db: BizarreDatabase): AppliedMigrationDao = db.appliedMigrationDao()
    @Provides fun provideSyncStateDao(db: BizarreDatabase): SyncStateDao = db.syncStateDao()
    @Provides fun provideParkedCartDao(db: BizarreDatabase): com.bizarreelectronics.crm.data.local.db.dao.ParkedCartDao = db.parkedCartDao()
}
