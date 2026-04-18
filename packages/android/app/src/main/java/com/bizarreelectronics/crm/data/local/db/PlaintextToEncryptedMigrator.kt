package com.bizarreelectronics.crm.data.local.db

import android.content.Context
import android.database.sqlite.SQLiteException
import android.util.Log
import net.zetetic.database.sqlcipher.SQLiteDatabase as CipherSQLiteDatabase
import java.io.File

/**
 * One-shot upgrade path for pre-SQLCipher installs.
 *
 * Background: builds shipped before the SQLCipher rollout stored the Room
 * database as a plaintext SQLite file at `context.getDatabasePath("bizarre_crm.db")`.
 * Opening that same file with [net.zetetic.database.sqlcipher.SupportOpenHelperFactory]
 * fails with "file is not a database" because SQLCipher expects an encrypted
 * header. Without a migration step users of the old build would hit an
 * app-start crash after upgrade (AUD-20260414-M4).
 *
 * What this class does, once per install, guarded by the
 * [KEY_MIGRATION_DONE] flag in [PREFS_FILE_NAME]:
 *
 *   1. Inspect `bizarre_crm.db`. If it does not exist (fresh install), mark
 *      the flag done and return — Room will create an encrypted DB from
 *      scratch.
 *   2. Try to open the file as plaintext with the system SQLite. If the open
 *      fails it is almost certainly already encrypted (or corrupt beyond our
 *      scope) — mark the flag done and return so Room can take over.
 *   3. Clean any leftover staging artifacts from a previous partial run
 *      (`bizarre_crm.db.enc.tmp` + journal/wal/shm companions).
 *   4. Open the plaintext file again with the SQLCipher build of SQLite
 *      (empty key). Attach an empty encrypted database at the staging path
 *      with the passphrase from [com.bizarreelectronics.crm.data.local.prefs.DatabasePassphrase].
 *      Call `SELECT sqlcipher_export('encrypted')` to copy every row from
 *      `main` into the attached encrypted database in a single pass.
 *   5. Rename the old plaintext file to `bizarre_crm.legacy.db` (quarantined,
 *      NOT deleted — safety net if something downstream corrupts the new
 *      DB). Rename the staging encrypted file to `bizarre_crm.db`. Move
 *      journal/wal/shm sidecars with the same pattern.
 *   6. Set [KEY_MIGRATION_DONE] = true so the next app start skips everything
 *      above in O(1) time.
 *
 * Failure modes:
 *   - Insufficient storage mid-copy: we throw a [MigrationFailedException] so
 *     the caller can surface a user-visible error before Room tries to open
 *     the (still-plaintext) file and crashes harder. The staging file is
 *     unlinked on its way out.
 *   - `sqlcipher_export` throws: same path as above. The original plaintext
 *     file is untouched, so the user's data is not lost.
 *
 * Thread safety: called from exactly one place (DatabaseModule.provideDatabase)
 * which is itself called once per process by Hilt. The internal file ops are
 * not thread-safe and rely on that contract.
 */
object PlaintextToEncryptedMigrator {

    private const val TAG = "PlaintextToEncryptedMigrator"

    /** Non-encrypted SharedPreferences file for the migration flag. */
    internal const val PREFS_FILE_NAME = "sqlcipher_migration_prefs"

    /**
     * Persistent boolean flag. Set after a successful migration (or after we
     * determine no migration is needed). Controls idempotence.
     */
    internal const val KEY_MIGRATION_DONE = "sqlcipher_migration_v1_done"

    /** Main database file, must match [BizarreDatabase.DATABASE_NAME]. */
    private const val DB_NAME = BizarreDatabase.DATABASE_NAME

    /** Quarantine name for the pre-upgrade plaintext file. Never deleted. */
    private const val LEGACY_NAME = "bizarre_crm.legacy.db"

    /** Staging name while we build the encrypted copy. */
    private const val STAGING_NAME = "bizarre_crm.db.enc.tmp"

    /**
     * Sidecars SQLite creates next to the main DB file. Same prefix, different
     * suffixes. We move / clean these alongside the main file so that renaming
     * to `.db` does not leave a stale journal pointing at the old header.
     */
    private val SIDECAR_SUFFIXES = listOf("-journal", "-wal", "-shm")

    /**
     * Run the migration if needed. Safe to call on every app start. Returns
     * silently on no-op paths; throws [MigrationFailedException] only when
     * plaintext data was detected and we could not produce an encrypted copy.
     *
     * @param context any [Context] (application context is used internally).
     * @param passphraseHexChars hex-encoded SQLCipher passphrase, same shape
     *        produced by [com.bizarreelectronics.crm.data.local.prefs.DatabasePassphrase.loadOrCreate].
     */
    fun migrateIfNeeded(context: Context, passphraseHexChars: CharArray) {
        val appContext = context.applicationContext
        val prefs = appContext.getSharedPreferences(PREFS_FILE_NAME, Context.MODE_PRIVATE)
        if (prefs.getBoolean(KEY_MIGRATION_DONE, false)) {
            return
        }

        val dbFile = appContext.getDatabasePath(DB_NAME)
        ensureParentDirExists(dbFile)

        if (!dbFile.exists()) {
            // Fresh install: nothing to migrate. Marking done here means we
            // never re-check on subsequent launches.
            Log.i(TAG, "No existing DB file — marking migration done (fresh install).")
            markDone(prefs)
            return
        }

        if (!isPlaintextSqlite(dbFile)) {
            // File exists but is not a plaintext SQLite DB (either already
            // encrypted or a partial write from a prior launch that Room will
            // fail on). Either way, running the migrator against it would do
            // more harm than good, so we mark done and let Room surface any
            // issue normally.
            Log.i(TAG, "Existing DB file is not readable as plaintext — skipping migration.")
            markDone(prefs)
            return
        }

        // Clean any stale staging artifacts from a previous partial run.
        val stagingFile = File(dbFile.parentFile, STAGING_NAME)
        deleteIfExists(stagingFile)
        for (suffix in SIDECAR_SUFFIXES) {
            deleteIfExists(File(dbFile.parentFile, STAGING_NAME + suffix))
        }

        try {
            exportPlaintextToEncrypted(
                plaintextFile = dbFile,
                encryptedStagingFile = stagingFile,
                passphraseHexChars = passphraseHexChars,
            )
        } catch (t: Throwable) {
            // Roll back staging files so the next attempt starts clean.
            deleteIfExists(stagingFile)
            for (suffix in SIDECAR_SUFFIXES) {
                deleteIfExists(File(dbFile.parentFile, STAGING_NAME + suffix))
            }
            Log.e(TAG, "SQLCipher export failed — plaintext DB left in place.", t)
            throw MigrationFailedException(
                "Unable to upgrade local database to encrypted storage. " +
                    "This usually means the device is out of free space. " +
                    "Free some storage and relaunch the app.",
                t,
            )
        }

        // Swap in the encrypted file. At this point:
        //   - `dbFile` = plaintext, intact
        //   - `stagingFile` = encrypted, contains every row from the plaintext DB
        // We want:
        //   - `LEGACY_NAME` = plaintext, kept as safety net
        //   - `dbFile` (= DB_NAME) = encrypted
        val legacyFile = File(dbFile.parentFile, LEGACY_NAME)
        deleteIfExists(legacyFile)
        for (suffix in SIDECAR_SUFFIXES) {
            deleteIfExists(File(dbFile.parentFile, LEGACY_NAME + suffix))
        }

        // Move plaintext → legacy (including sidecars).
        renameOrThrow(dbFile, legacyFile)
        for (suffix in SIDECAR_SUFFIXES) {
            val src = File(dbFile.parentFile, DB_NAME + suffix)
            if (src.exists()) {
                renameOrThrow(src, File(dbFile.parentFile, LEGACY_NAME + suffix))
            }
        }

        // Move encrypted staging → live DB (including sidecars).
        renameOrThrow(stagingFile, dbFile)
        for (suffix in SIDECAR_SUFFIXES) {
            val src = File(dbFile.parentFile, STAGING_NAME + suffix)
            if (src.exists()) {
                renameOrThrow(src, File(dbFile.parentFile, DB_NAME + suffix))
            }
        }

        markDone(prefs)
        Log.i(TAG, "Migrated plaintext DB to SQLCipher")
    }

    /**
     * Run `sqlcipher_export` from an empty-key-opened plaintext DB into an
     * attached encrypted DB. SQLCipher's recipe:
     *
     *   ATTACH DATABASE '<encrypted.db>' AS encrypted KEY "x'<hex>'";
     *   SELECT sqlcipher_export('encrypted');
     *   DETACH DATABASE encrypted;
     *
     * `KEY "x'<hex>'"` tells SQLCipher the CharArray is a raw 64-char hex key
     * rather than a passphrase that needs PBKDF2 key derivation — matches how
     * [com.bizarreelectronics.crm.di.DatabaseModule] feeds the key to Room.
     */
    private fun exportPlaintextToEncrypted(
        plaintextFile: File,
        encryptedStagingFile: File,
        passphraseHexChars: CharArray,
    ) {
        // The SQLCipher native library is loaded once in
        // [com.bizarreelectronics.crm.BizarreCrmApp.onCreate] via
        // `System.loadLibrary("sqlcipher")`. The migrator is invoked from
        // `DatabaseModule.provideDatabase`, which Hilt only resolves after
        // Application.onCreate completes, so the symbols are in place by the
        // time we touch [CipherSQLiteDatabase].

        // Open the plaintext DB with the SQLCipher build of SQLite. An empty
        // passphrase bypasses SQLCipher's encryption layer — the file is read
        // as a standard SQLite database. This is the canonical recipe for
        // upgrading an existing plaintext DB to encrypted.
        //
        // Note: we open read-write (not read-only) because SQLite's ATTACH
        // statement can require a write-capable primary connection when the
        // attached database is created. Our source file is not mutated —
        // `sqlcipher_export` only reads from main.
        val plaintextDb = CipherSQLiteDatabase.openDatabase(
            plaintextFile.absolutePath,
            /* password = */ "",
            /* factory = */ null,
            /* flags = */ CipherSQLiteDatabase.OPEN_READWRITE,
            /* hook = */ null,
        )
        try {
            // ATTACH DATABASE in SQLite does not always accept ? bind params
            // for the filename or key. Both values come from trusted internal
            // sources (app's own database directory + hex passphrase from
            // EncryptedSharedPreferences), but we still sanitize the path to
            // reject embedded single quotes out of paranoia.
            val attachPath = encryptedStagingFile.absolutePath
            require(!attachPath.contains('\'')) {
                "Database path must not contain single quotes: $attachPath"
            }
            val hexKeyLiteral = "\"x'" + String(passphraseHexChars) + "'\""
            plaintextDb.execSQL(
                "ATTACH DATABASE '$attachPath' AS encrypted KEY $hexKeyLiteral"
            )
            try {
                // rawQuery so the pragma-style SELECT actually runs. We
                // iterate the cursor so the statement executes fully.
                plaintextDb.rawQuery("SELECT sqlcipher_export('encrypted')", null as Array<String>?)
                    .use { c -> c.moveToFirst() }
            } finally {
                plaintextDb.execSQL("DETACH DATABASE encrypted")
            }
        } finally {
            plaintextDb.close()
        }
    }

    /**
     * Quick sniff test: try to open the file as a plaintext SQLite database
     * with the system `android.database.sqlite` API. If the header is a
     * SQLCipher ciphertext header, [openDatabase] throws [SQLiteException]
     * ("file is not a database" or similar) because the system API cannot
     * decrypt.
     */
    private fun isPlaintextSqlite(file: File): Boolean {
        return try {
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(
                file.absolutePath,
                null,
                android.database.sqlite.SQLiteDatabase.OPEN_READONLY,
            )
            db.close()
            true
        } catch (_: SQLiteException) {
            false
        } catch (_: Throwable) {
            // Be conservative — any unexpected failure means "don't touch it".
            false
        }
    }

    private fun markDone(prefs: android.content.SharedPreferences) {
        prefs.edit().putBoolean(KEY_MIGRATION_DONE, true).apply()
    }

    private fun ensureParentDirExists(dbFile: File) {
        val parent = dbFile.parentFile ?: return
        if (!parent.exists()) {
            parent.mkdirs()
        }
    }

    private fun deleteIfExists(file: File) {
        if (file.exists() && !file.delete()) {
            Log.w(TAG, "Could not delete ${file.absolutePath}")
        }
    }

    private fun renameOrThrow(src: File, dst: File) {
        if (!src.renameTo(dst)) {
            throw MigrationFailedException(
                "Could not rename ${src.absolutePath} to ${dst.absolutePath}. " +
                    "Your device may be out of free space.",
                cause = null,
            )
        }
    }

    /**
     * Thrown when the migration detects plaintext data but cannot produce a
     * usable encrypted copy. The caller should surface this to the user as a
     * "free up space and retry" message rather than allow Room to proceed and
     * crash on open.
     */
    class MigrationFailedException(
        message: String,
        cause: Throwable?,
    ) : RuntimeException(message, cause)
}
