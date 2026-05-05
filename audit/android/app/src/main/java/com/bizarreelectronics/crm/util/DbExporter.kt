package com.bizarreelectronics.crm.util

import android.content.ContentResolver
import android.net.Uri
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * DbExporter — zipped snapshot helper for Settings → Diagnostics → Export DB.
 *
 * The local Room database is encrypted with SQLCipher. This helper exports the
 * raw encrypted files (main `.db`, WAL, and SHM sidecars) into a ZIP archive at
 * the caller-supplied SAF [Uri]. The resulting archive **cannot** be opened as a
 * plain SQLite file without the passphrase used at encryption time.
 *
 * A warning header file (`!READ_ME.txt`) is prepended to the ZIP so that anyone
 * who opens the archive understands it is encrypted and is intended for developer
 * inspection only (e.g. after extracting the plaintext via `sqlcipher_export`).
 *
 * Usage:
 * ```kotlin
 * DbExporter.export(
 *     databasesDir = context.getDatabasePath("bizarre-crm.db").parentFile!!,
 *     dbName       = "bizarre-crm.db",
 *     resolver     = context.contentResolver,
 *     destUri      = safUri,
 *     onProgress   = { bytesWritten -> … },
 * )
 * ```
 *
 * Immutability: all parameters are read-only; the function creates only new
 * streams and does not mutate the source files.
 *
 * Thread safety: this is a blocking call — invoke from an IO dispatcher
 * (e.g. [kotlinx.coroutines.Dispatchers.IO]).
 *
 * [plan:L185] — ActionPlan §1.3 line 185.
 */
object DbExporter {

    private const val README_ENTRY = "!READ_ME.txt"

    private val README_TEXT = """
        BIZARRE CRM — ENCRYPTED DATABASE SNAPSHOT
        ==========================================
        This archive contains raw SQLCipher-encrypted database files.
        They CANNOT be opened as a plain SQLite database.

        To inspect the data:
          1. Obtain the passphrase from the app's SecretManager / Keystore.
          2. Open each .db file with an SQLCipher-aware tool (e.g. DB Browser
             for SQLite with the SQLCipher extension, or the sqlcipher CLI).
          3. Run `PRAGMA key = '<passphrase>';` before any query.

        Files included:
          • bizarre-crm.db       — main database
          • bizarre-crm.db-wal   — write-ahead log (if present)
          • bizarre-crm.db-shm   — shared memory file (if present)

        This export is for DEVELOPER USE ONLY. Delete it after inspection.
    """.trimIndent()

    /**
     * Exports [dbName] and its sidecars (`-wal`, `-shm`) from [databasesDir]
     * into a ZIP written to [destUri] via [resolver].
     *
     * @param databasesDir  The directory returned by `context.getDatabasePath(name).parentFile`.
     * @param dbName        Filename of the main database (e.g. `"bizarre-crm.db"`).
     * @param resolver      Application [ContentResolver] used to open the output stream.
     * @param destUri       SAF [Uri] chosen by the user via [ActivityResultContracts.CreateDocument].
     * @param onProgress    Called with cumulative bytes written so far (approximate; per-entry).
     *
     * @throws SecurityException if the caller does not hold write permission to [destUri].
     * @throws IOException       if any read or write operation fails.
     * @throws IllegalStateException if [resolver] returns a null output stream for [destUri].
     */
    @Throws(SecurityException::class, IOException::class, IllegalStateException::class)
    fun export(
        databasesDir: File,
        dbName: String,
        resolver: ContentResolver,
        destUri: Uri,
        onProgress: (bytesWritten: Long) -> Unit = {},
    ): Long {
        val outStream = resolver.openOutputStream(destUri)
            ?: throw IllegalStateException("ContentResolver returned null output stream for $destUri")

        var totalBytes = 0L

        outStream.use { raw ->
            ZipOutputStream(raw.buffered()).use { zip ->
                // Prepend the human-readable warning so it appears first in
                // archive listings (! sorts before alphanumeric).
                zip.putNextEntry(ZipEntry(README_ENTRY))
                val readmeBytes = README_TEXT.toByteArray(Charsets.UTF_8)
                zip.write(readmeBytes)
                zip.closeEntry()
                totalBytes += readmeBytes.size
                onProgress(totalBytes)

                // Collect main DB + optional sidecars. Order: main → wal → shm
                // so that restoring with `cp` in correct order is straightforward.
                val sidecars = listOf(dbName, "$dbName-wal", "$dbName-shm")
                for (fileName in sidecars) {
                    val file = File(databasesDir, fileName)
                    if (!file.exists()) continue
                    zip.putNextEntry(ZipEntry(fileName))
                    totalBytes += copyFile(file, zip, totalBytes, onProgress)
                    zip.closeEntry()
                }
            }
        }

        return totalBytes
    }

    /**
     * Streams [source] into [zip] using a fixed-size buffer, calling [onProgress]
     * after each chunk so the UI can update a progress indicator.
     *
     * Returns the number of bytes read from [source].
     */
    private fun copyFile(
        source: File,
        zip: ZipOutputStream,
        cumulativeSoFar: Long,
        onProgress: (Long) -> Unit,
    ): Long {
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE) // 8 KiB — matches JVM default
        var bytesCopied = 0L
        FileInputStream(source).use { fis ->
            var read = fis.read(buffer)
            while (read >= 0) {
                zip.write(buffer, 0, read)
                bytesCopied += read
                onProgress(cumulativeSoFar + bytesCopied)
                read = fis.read(buffer)
            }
        }
        return bytesCopied
    }
}
