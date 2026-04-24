package com.bizarreelectronics.crm.data.local.db

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import timber.log.Timber
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.system.exitProcess

/**
 * Guards the Room database against two failure modes and performs a
 * backup-before-migrate step before Room opens the DB file.
 *
 * ## Responsibilities
 *
 * ### 1. Backup before migrate (Line 219)
 *
 * [backupIfNeeded] copies the live database file to
 * `cacheDir/db-backups/pre-migration-<yyyyMMdd-HHmmss>.db` before Room is
 * opened. If the migration then corrupts the DB, the user can restore from the
 * backup without data loss. Backups older than 7 days (or all but the most
 * recent one after a successful launch) are pruned automatically.
 *
 * ### 2. Forward-only enforcement (Line 217)
 *
 * [checkForwardOnly] reads the schema version stored in SharedPreferences at
 * the last successful launch. If the DB file on disk has a *higher* schema
 * version than this build supports (e.g. user downgraded the APK), the app
 * exits with code 2 and a clear log message. The DB is never mutated — the
 * exit is the safeguard.
 *
 * ### 3. Debug dry-run (Line 220)
 *
 * [dryRunOnBackupIfDebug] (called when [android.os.Build.VERSION.SDK_INT] is
 * accessible and [com.bizarreelectronics.crm.BuildConfig.DEBUG] is `true`) opens
 * the *backup copy* — not the live DB — runs `PRAGMA integrity_check`, and
 * logs the result via [Timber]. Skipped entirely on release builds.
 *
 * Thread safety: all public methods are called from a single-threaded Hilt
 * provider before Room's builder is finalised, so no concurrent access is
 * possible.
 */
object DatabaseGuard {

    private const val TAG = "DatabaseGuard"

    private const val PREFS_NAME = "db_guard_prefs"
    private const val KEY_LAST_KNOWN_VERSION = "last_known_schema_version"
    private const val BACKUP_DIR_NAME = "db-backups"
    private const val MAX_BACKUP_AGE_MS = 7L * 24 * 60 * 60 * 1_000 // 7 days
    private val BACKUP_DATE_FORMAT = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US)

    // -------------------------------------------------------------------------
    // Backup before migrate (Line 219)
    // -------------------------------------------------------------------------

    /**
     * Copy the live DB file to the backup directory.
     *
     * Safe to call even when the DB file does not yet exist (fresh install) —
     * the method returns without creating a backup. WAL sidecars are included
     * when present.
     *
     * @param context application context.
     * @return the backup [File] that was created, or null if no backup was
     *   needed (fresh install or source not readable).
     */
    fun backupIfNeeded(context: Context): File? {
        val dbFile = context.getDatabasePath(BizarreDatabase.DATABASE_NAME)
        if (!dbFile.exists() || !dbFile.canRead()) {
            Timber.tag(TAG).d("No existing DB file — skipping pre-migration backup.")
            return null
        }

        val backupDir = File(context.cacheDir, BACKUP_DIR_NAME).also { it.mkdirs() }
        val timestamp = BACKUP_DATE_FORMAT.format(Date())
        val backupFile = File(backupDir, "pre-migration-$timestamp.db")

        return try {
            dbFile.copyTo(backupFile, overwrite = false)
            // Copy WAL and SHM sidecars if present.
            for (suffix in listOf("-wal", "-shm")) {
                val sidecar = File(dbFile.parent, dbFile.name + suffix)
                if (sidecar.exists()) {
                    sidecar.copyTo(File(backupDir, backupFile.name + suffix), overwrite = false)
                }
            }
            Timber.tag(TAG).i("Pre-migration backup created: ${backupFile.absolutePath}")
            pruneOldBackups(backupDir)
            backupFile
        } catch (e: Exception) {
            Timber.tag(TAG).w(e, "Pre-migration backup failed — proceeding without backup.")
            null
        }
    }

    /**
     * Delete backup files older than [MAX_BACKUP_AGE_MS]. Called automatically
     * after each successful backup in [backupIfNeeded].
     */
    private fun pruneOldBackups(backupDir: File) {
        val cutoff = System.currentTimeMillis() - MAX_BACKUP_AGE_MS
        backupDir.listFiles()
            ?.filter { it.isFile && it.lastModified() < cutoff }
            ?.forEach { stale ->
                if (stale.delete()) {
                    Timber.tag(TAG).d("Pruned stale backup: ${stale.name}")
                } else {
                    Timber.tag(TAG).w("Could not delete stale backup: ${stale.name}")
                }
            }
    }

    // -------------------------------------------------------------------------
    // Forward-only check (Line 217)
    // -------------------------------------------------------------------------

    /**
     * Guard against database downgrade.
     *
     * Reads the schema version stored at the last successful app launch from
     * [PREFS_NAME]. If the stored version is greater than the schema version
     * this build targets, the app exits with code 2 — a DB built by a newer
     * APK cannot safely be opened by an older APK.
     *
     * Call this *before* Room opens the DB so a potentially-incompatible file
     * is never handed to the Room runtime.
     *
     * @param context application context.
     * @param currentBuildVersion the schema version this build was compiled
     *   against — pass [BizarreDatabase.SCHEMA_VERSION].
     */
    fun checkForwardOnly(context: Context, currentBuildVersion: Int) {
        val prefs = guardPrefs(context)
        val lastKnown = prefs.getInt(KEY_LAST_KNOWN_VERSION, 0)

        if (lastKnown > currentBuildVersion) {
            // The DB on disk was written by a newer build. Opening it with this
            // build's Room code would either crash Room (if new columns are
            // referenced in DAOs that don't exist here) or silently return
            // incorrect data (if new columns are simply absent). Neither is safe.
            Log.e(
                TAG,
                "FATAL: database version $lastKnown is newer than this app's " +
                    "schema version $currentBuildVersion. " +
                    "The app has been downgraded. Exiting with code 2. " +
                    "Contact Bizarre Electronics support."
            )
            exitProcess(2)
        }
    }

    /**
     * Persist the schema version after a successful Room open so [checkForwardOnly]
     * can compare it on the next launch.
     *
     * Call this inside [RoomDatabase.Callback.onOpen] after all validation passes.
     */
    fun recordSuccessfulOpen(context: Context, version: Int) {
        guardPrefs(context).edit().putInt(KEY_LAST_KNOWN_VERSION, version).apply()
    }

    // -------------------------------------------------------------------------
    // Debug dry-run (Line 220)
    // -------------------------------------------------------------------------

    /**
     * In DEBUG builds: run `PRAGMA integrity_check` on the *backup copy* of the
     * database and log the result via Timber.
     *
     * If no backup was created for this launch (fresh install) the method is a
     * no-op. On release builds the call is compiled out via the [isDebug]
     * parameter — callers pass [com.bizarreelectronics.crm.BuildConfig.DEBUG].
     *
     * @param backupFile the file returned by [backupIfNeeded]; pass null to skip.
     * @param isDebug [BuildConfig.DEBUG] value from the caller.
     */
    fun dryRunOnBackupIfDebug(backupFile: File?, isDebug: Boolean) {
        if (!isDebug || backupFile == null || !backupFile.exists()) return

        try {
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(
                backupFile.absolutePath,
                null,
                android.database.sqlite.SQLiteDatabase.OPEN_READONLY,
            )
            db.use { sqlite ->
                sqlite.rawQuery("PRAGMA integrity_check", null).use { cursor ->
                    val results = buildList {
                        while (cursor.moveToNext()) {
                            add(cursor.getString(0))
                        }
                    }
                    val summary = results.take(10).joinToString(" | ")
                    Timber.tag(TAG).d("Backup integrity_check result: $summary")
                    if (results.size == 1 && results[0] == "ok") {
                        Timber.tag(TAG).d("Backup DB integrity: OK")
                    } else {
                        Timber.tag(TAG).w("Backup DB integrity issues detected: $summary")
                    }
                }
            }
        } catch (e: Exception) {
            // Backup is an unencrypted copy from before SQLCipher opens the live
            // DB. If the live DB is encrypted and we have no plaintext backup,
            // opening with the system SQLite will throw. Log and move on.
            Timber.tag(TAG).d(e, "Could not run integrity_check on backup (may be encrypted — expected).")
        }
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    private fun guardPrefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
