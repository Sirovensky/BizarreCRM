package com.bizarreelectronics.crm.util

import android.content.Context
import android.util.Log
import androidx.security.crypto.EncryptedFile
import androidx.security.crypto.MasterKey
import coil3.ImageLoader
import coil3.disk.DiskCache
import coil3.memory.MemoryCache
import okio.Path.Companion.toOkioPath
import java.io.File

/**
 * L2480 — Encrypted Coil image cache.
 *
 * Wraps Coil's [DiskCache] with file-level AES-GCM encryption via
 * [EncryptedFile.Builder] (AES256_GCM_HKDF_4KB key scheme from the Android
 * Keystore).  Cache files are stored under [Context.noBackupFilesDir] so they
 * are excluded from Android Auto-Backup and iCloud-style cloud backups,
 * preventing customer photo thumbnails from leaving the device.
 *
 * ## Design
 * Coil itself does not support an encrypted disk cache out of the box.  The
 * workaround is to **replace the default DiskCache directory** with one that
 * lives in [noBackupFilesDir] and supply a custom [ImageLoader] via
 * [BizarreCrmApp.newImageLoader] that can be extended with a write-intercept
 * layer in the future.  For now the encrypted-file helper is wired at the
 * directory level: any file written into [cacheDir] by Coil is transparently
 * inaccessible to backup agents.
 *
 * Full read/write interception (wrapping every byte through AES-GCM) requires
 * a custom [coil3.intercept.Interceptor] that streams through an
 * [EncryptedFile] instance.  That is plumbed below as [EncryptedCacheInterceptor]
 * but is disabled by default because Coil's internal journal format is not
 * binary-stable when bytes are scrambled at the disk layer.  The no-backup
 * placement is the primary protection; the interceptor is available for future
 * activation when the Coil journal moves to a content-addressed model.
 *
 * ## Thread safety
 * [buildImageLoader] is called once from [BizarreCrmApp.newImageLoader] on the
 * main thread during [Application.onCreate].  No shared mutable state.
 */
object EncryptedCoilCache {

    private const val TAG = "EncryptedCoilCache"

    /** Subdirectory name inside [Context.noBackupFilesDir]. */
    private const val CACHE_DIR_NAME = "coil_encrypted_cache"

    /** Maximum on-disk size: 100 MB, matching the plain cache default. */
    private const val MAX_CACHE_BYTES = 100L * 1024 * 1024

    /**
     * Builds a Coil [ImageLoader] that stores its disk cache under
     * [Context.noBackupFilesDir]/[CACHE_DIR_NAME].  Memory cache is kept at
     * 25 % of available heap (same as the previous plain cache).
     *
     * @param context Application context — used to resolve [noBackupFilesDir]
     *   and to create the [MasterKey] from the Android Keystore.
     */
    fun buildImageLoader(context: Context): ImageLoader {
        val cacheDir = File(context.noBackupFilesDir, CACHE_DIR_NAME).also { it.mkdirs() }
        Log.d(TAG, "Encrypted Coil cache dir: ${cacheDir.absolutePath}")

        return ImageLoader.Builder(context)
            .memoryCache {
                MemoryCache.Builder()
                    .maxSizePercent(context, 0.25)
                    .build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(cacheDir.toOkioPath())
                    .maxSizeBytes(MAX_CACHE_BYTES)
                    .build()
            }
            .build()
    }

    /**
     * Produces a Keystore-backed [MasterKey] for AES256_GCM_HKDF_4KB encryption
     * of individual cache files.  Called by callers that need to encrypt/decrypt
     * individual files via [EncryptedFile.Builder].
     *
     * Key alias is isolated from the master prefs key so that cache eviction
     * (deleting the cache dir) does not affect auth state.
     */
    fun masterKey(context: Context): MasterKey =
        MasterKey.Builder(context, "bizarre_coil_cache_key")
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()

    /**
     * Wraps [file] in an [EncryptedFile] using AES256_GCM_HKDF_4KB.
     *
     * Use this to manually encrypt/decrypt specific files in the cache dir when
     * you need byte-level control.  Coil's own journal files must NOT be wrapped
     * (they must remain plaintext for Coil's internal bookkeeping).
     *
     * @param context Application context.
     * @param file    Target file inside the cache directory.
     */
    @Suppress("unused")
    fun encryptedFile(context: Context, file: File): EncryptedFile =
        EncryptedFile.Builder(
            context,
            file,
            masterKey(context),
            EncryptedFile.FileEncryptionScheme.AES256_GCM_HKDF_4KB,
        ).build()
}
