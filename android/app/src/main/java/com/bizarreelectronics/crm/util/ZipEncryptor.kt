package com.bizarreelectronics.crm.util

import android.content.ContentResolver
import android.net.Uri
import net.lingala.zip4j.io.outputstream.ZipOutputStream
import net.lingala.zip4j.model.ZipParameters
import net.lingala.zip4j.model.enums.AesKeyStrength
import net.lingala.zip4j.model.enums.CompressionMethod
import net.lingala.zip4j.model.enums.EncryptionMethod
import java.io.InputStream

/**
 * §51.4 — ZipEncryptor
 *
 * Wraps net.lingala.zip4j to produce an AES-256 password-protected ZIP from
 * an arbitrary [InputStream] obtained from the server export download.
 *
 * Usage:
 * ```kotlin
 * ZipEncryptor.encryptToSafUri(
 *     sourceStream  = serverResponseBody.byteStream(),
 *     entryName     = "export_csv.csv",
 *     password      = "s3cr3t",
 *     resolver      = context.contentResolver,
 *     destUri       = safUri,
 * )
 * ```
 *
 * Design choices:
 * - AES 256-bit key strength (`AES_KEY_STRENGTH_256`) — maximum protection
 *   available in zip4j; ZIP-native AES (WinZip AES) compatible with 7-Zip,
 *   macOS Archive Utility (from macOS 10.15+), and most modern unzippers.
 * - DEFLATE compression applied before encryption so the archive size matches
 *   a regular ZIP (no double-compress overhead because the server already
 *   exports in a compact format).
 * - Password is a `CharArray` rather than a `String` to allow the caller to
 *   zero-fill it after use, limiting its GC lifetime in heap.
 * - No external storage permission required — all I/O goes through the SAF
 *   [ContentResolver] `openOutputStream` granted by `ACTION_CREATE_DOCUMENT`.
 *
 * Thread safety: none — callers must dispatch to an IO dispatcher (e.g.
 * `withContext(Dispatchers.IO)`).
 */
object ZipEncryptor {

    /**
     * Read all bytes from [sourceStream] and write them into a password-protected
     * AES-256 ZIP entry named [entryName], streaming the result to [destUri]
     * via [resolver].
     *
     * @param sourceStream  Raw bytes to protect (server export body stream).
     * @param entryName     File name used for the single entry inside the ZIP.
     *                      Should match the export format, e.g. "export_csv.csv".
     * @param password      Plaintext password as a [CharArray]. Caller should
     *                      zero-fill after this call returns.
     * @param resolver      [ContentResolver] from which the SAF output stream is
     *                      obtained.
     * @param destUri       SAF [Uri] granted by `ACTION_CREATE_DOCUMENT`.
     * @throws IllegalStateException if [resolver] cannot open [destUri] for
     *                               writing.
     */
    fun encryptToSafUri(
        sourceStream: InputStream,
        entryName: String,
        password: CharArray,
        resolver: ContentResolver,
        destUri: Uri,
    ) {
        val params = ZipParameters().apply {
            compressionMethod = CompressionMethod.DEFLATE
            isEncryptFiles = true
            encryptionMethod = EncryptionMethod.AES
            aesKeyStrength = AesKeyStrength.KEY_STRENGTH_256
            fileNameInZip = entryName
        }

        val outputStream = resolver.openOutputStream(destUri)
            ?: throw IllegalStateException("Could not open output stream for URI: $destUri")

        ZipOutputStream(outputStream, password).use { zipOut ->
            zipOut.putNextEntry(params)
            sourceStream.use { it.copyTo(zipOut) }
            zipOut.closeEntry()
        }
    }

    /**
     * Produce a suggested ZIP file name for the SAF [ACTION_CREATE_DOCUMENT]
     * launcher from the original export file name.
     *
     * "export_csv.csv"  → "export_csv.zip"
     * "export_json.json" → "export_json.zip"
     */
    fun suggestZipName(originalName: String): String {
        val base = originalName.substringBeforeLast(".")
        return "$base.zip"
    }
}
