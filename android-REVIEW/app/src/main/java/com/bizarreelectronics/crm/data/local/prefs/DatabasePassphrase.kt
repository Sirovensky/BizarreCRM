package com.bizarreelectronics.crm.data.local.prefs

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.security.SecureRandom

/**
 * Per-install SQLCipher passphrase storage.
 *
 * Generates a 32-byte random passphrase on first run and persists it to an
 * [EncryptedSharedPreferences] file (AES256_SIV keys + AES256_GCM values,
 * master key from the Android Keystore). Subsequent calls return the same
 * bytes from disk. The passphrase never appears in plaintext on disk and
 * never leaves the device.
 *
 * This lives in its OWN prefs file ("db_passphrase_prefs") rather than
 * piggybacking on [AuthPreferences]. The reason is lifecycle: [AuthPreferences]
 * gets cleared on logout, but the SQLCipher passphrase must survive logout
 * — otherwise the next login would fail to open the existing encrypted DB.
 *
 * Thread safety: [loadOrCreate] is idempotent and safe to call from any
 * thread. The first call from any thread will generate + persist; subsequent
 * calls read from disk. A process-wide synchronized block guards against
 * two threads racing to generate two different passphrases on first launch.
 *
 * Callers should:
 *   1. Call [loadOrCreate] once at database construction time.
 *   2. Hand the returned [CharArray] to SQLCipher's `SupportFactory`.
 *   3. NOT hold on to the passphrase longer than necessary — Room keeps
 *      its own copy internally, so the caller can let the reference go
 *      once the database has been opened. (We still return CharArray
 *      rather than String so that in-memory zeroing remains possible
 *      in a future hardening pass.)
 */
object DatabasePassphrase {

    private const val PREFS_FILE_NAME = "db_passphrase_prefs"
    private const val KEY_PASSPHRASE_HEX = "sqlcipher_passphrase_hex"
    private const val PASSPHRASE_BYTES = 32

    private val lock = Any()

    /**
     * Returns the SQLCipher passphrase for this install, generating and
     * persisting one on first call. Safe to call repeatedly.
     *
     * @param context any [Context] — we use the application context
     *                internally so it is fine to pass an Activity.
     */
    fun loadOrCreate(context: Context): CharArray {
        synchronized(lock) {
            val prefs = openPrefs(context.applicationContext)
            val existingHex = prefs.getString(KEY_PASSPHRASE_HEX, null)
            if (existingHex != null) {
                return hexToChars(existingHex)
            }
            val fresh = ByteArray(PASSPHRASE_BYTES).also { SecureRandom().nextBytes(it) }
            val hex = bytesToHex(fresh)
            prefs.edit().putString(KEY_PASSPHRASE_HEX, hex).apply()
            // Zero the raw byte buffer before returning — the string in prefs
            // is all we need going forward.
            fresh.fill(0)
            return hexToChars(hex)
        }
    }

    private fun openPrefs(context: Context) = EncryptedSharedPreferences.create(
        context,
        PREFS_FILE_NAME,
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    private fun bytesToHex(bytes: ByteArray): String {
        val sb = StringBuilder(bytes.size * 2)
        for (b in bytes) {
            sb.append("%02x".format(b))
        }
        return sb.toString()
    }

    /**
     * Convert a hex-encoded string into a CharArray of its hex characters.
     * We feed SQLCipher the hex representation directly via
     * `SQLiteDatabase.getBytes(charArray)`, which understands raw hex keys.
     */
    private fun hexToChars(hex: String): CharArray = hex.toCharArray()
}
