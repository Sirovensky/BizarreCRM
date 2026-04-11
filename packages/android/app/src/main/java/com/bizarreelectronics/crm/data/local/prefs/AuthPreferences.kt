package com.bizarreelectronics.crm.data.local.prefs

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import java.security.SecureRandom
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Secure storage for auth state and per-install secrets.
 *
 * All values live in an [EncryptedSharedPreferences] instance, which encrypts
 * both keys (AES256_SIV) and values (AES256_GCM) using a master key from the
 * Android Keystore. That covers SEC3 (server URL previously in plaintext) —
 * there is only one preferences file and every field below is encrypted.
 *
 * In addition, [serverUrl] is protected by an HMAC-SHA256 signature stored in
 * a sibling key. Callers MUST use [setServerUrl] / [verifyServerUrlSignature]
 * so that tampering with the raw SharedPreferences file (e.g. via root or
 * backup restore) can be detected by the network layer and rejected.
 */
@Singleton
class AuthPreferences @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs: SharedPreferences = EncryptedSharedPreferences.create(
        context,
        "auth_prefs",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    /**
     * Emits Unit each time [clear] is called (e.g. after a failed token refresh).
     * Observe this in UI to redirect the user back to the login screen.
     * replay=0 so late subscribers don't get a stale event.
     */
    private val _authCleared = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val authCleared: SharedFlow<Unit> = _authCleared.asSharedFlow()

    // region — auth tokens

    var accessToken: String?
        get() = prefs.getString(KEY_ACCESS_TOKEN, null)
        set(value) = prefs.edit().putString(KEY_ACCESS_TOKEN, value).apply()

    var refreshToken: String?
        get() = prefs.getString(KEY_REFRESH_TOKEN, null)
        set(value) = prefs.edit().putString(KEY_REFRESH_TOKEN, value).apply()

    // endregion

    // region — user identity

    var userId: Long
        get() = prefs.getLong(KEY_USER_ID, 0)
        set(value) = prefs.edit().putLong(KEY_USER_ID, value).apply()

    var username: String?
        get() = prefs.getString(KEY_USERNAME, null)
        set(value) = prefs.edit().putString(KEY_USERNAME, value).apply()

    var userRole: String?
        get() = prefs.getString(KEY_USER_ROLE, null)
        set(value) = prefs.edit().putString(KEY_USER_ROLE, value).apply()

    var userFirstName: String?
        get() = prefs.getString(KEY_USER_FIRST_NAME, null)
        set(value) = prefs.edit().putString(KEY_USER_FIRST_NAME, value).apply()

    var userLastName: String?
        get() = prefs.getString(KEY_USER_LAST_NAME, null)
        set(value) = prefs.edit().putString(KEY_USER_LAST_NAME, value).apply()

    var storeName: String?
        get() = prefs.getString(KEY_STORE_NAME, null)
        set(value) = prefs.edit().putString(KEY_STORE_NAME, value).apply()

    // endregion

    // region — server URL (HMAC-protected)

    /**
     * Read-only getter. Writing via this property still works for legacy
     * callers (e.g. migration code) and automatically rewrites the HMAC.
     * Prefer [setServerUrl] in new code to make the intent explicit.
     */
    var serverUrl: String?
        get() = prefs.getString(KEY_SERVER_URL, null)
        set(value) = setServerUrl(value)

    fun setServerUrl(url: String?) {
        val editor = prefs.edit()
        if (url.isNullOrBlank()) {
            editor.remove(KEY_SERVER_URL)
            editor.remove(KEY_SERVER_URL_SIG)
        } else {
            editor.putString(KEY_SERVER_URL, url)
            editor.putString(KEY_SERVER_URL_SIG, computeServerUrlHmac(url))
        }
        editor.apply()
    }

    /**
     * Returns true if the HMAC-SHA256 signature of [url] matches the one
     * currently stored next to it. Used by the network layer to detect
     * tampering before redirecting traffic.
     *
     * If no signature has ever been written yet (e.g. a fresh install that
     * somehow has a serverUrl but no sig — should never happen via the
     * normal setter, only via direct SharedPreferences writes), the check
     * fails closed.
     */
    fun verifyServerUrlSignature(url: String): Boolean {
        val stored = prefs.getString(KEY_SERVER_URL_SIG, null) ?: return false
        val expected = computeServerUrlHmac(url)
        return constantTimeEquals(stored, expected)
    }

    private fun computeServerUrlHmac(url: String): String {
        val mac = Mac.getInstance(HMAC_ALGORITHM)
        mac.init(SecretKeySpec(installationSecret(), HMAC_ALGORITHM))
        val raw = mac.doFinal(url.toByteArray(Charsets.UTF_8))
        return raw.joinToString("") { b -> "%02x".format(b) }
    }

    /**
     * Timing-safe byte-for-byte comparison for hex HMAC strings.
     */
    private fun constantTimeEquals(a: String, b: String): Boolean {
        if (a.length != b.length) return false
        var diff = 0
        for (i in a.indices) {
            diff = diff or (a[i].code xor b[i].code)
        }
        return diff == 0
    }

    /**
     * Returns the raw bytes of the per-install HMAC key, generating one
     * lazily on first access and persisting it to the encrypted prefs.
     *
     * This is NOT a replacement for the Keystore master key — it rides on
     * top of EncryptedSharedPreferences, which itself is Keystore-backed.
     * The purpose is to make the HMAC unique per install so leaked pins
     * from one device can't be replayed on another.
     */
    private fun installationSecret(): ByteArray {
        val existing = prefs.getString(KEY_INSTALL_SECRET, null)
        if (existing != null) {
            return hexToBytes(existing)
        }
        val fresh = ByteArray(INSTALL_SECRET_BYTES).also { SecureRandom().nextBytes(it) }
        val hex = fresh.joinToString("") { b -> "%02x".format(b) }
        prefs.edit().putString(KEY_INSTALL_SECRET, hex).apply()
        return fresh
    }

    /**
     * Stable per-install identifier. Generated once on first access and
     * persisted. Use for crash reports, telemetry, analytics — NOT for auth.
     */
    val installationId: String
        get() {
            val existing = prefs.getString(KEY_INSTALL_ID, null)
            if (existing != null) return existing
            val fresh = UUID.randomUUID().toString()
            prefs.edit().putString(KEY_INSTALL_ID, fresh).apply()
            return fresh
        }

    private fun hexToBytes(hex: String): ByteArray {
        val out = ByteArray(hex.length / 2)
        for (i in out.indices) {
            out[i] = ((Character.digit(hex[i * 2], 16) shl 4) + Character.digit(hex[i * 2 + 1], 16)).toByte()
        }
        return out
    }

    // endregion

    val isLoggedIn: Boolean
        get() = accessToken != null

    /**
     * Clears auth + user identity fields. Deliberately preserves the
     * [serverUrl] (and its HMAC), [installationId] and [installationSecret]
     * so that after logout the user can log straight back in without
     * reconfiguring the server or breaking telemetry continuity.
     */
    fun clear() {
        val preservedUrl = prefs.getString(KEY_SERVER_URL, null)
        val preservedUrlSig = prefs.getString(KEY_SERVER_URL_SIG, null)
        val preservedInstallId = prefs.getString(KEY_INSTALL_ID, null)
        val preservedInstallSecret = prefs.getString(KEY_INSTALL_SECRET, null)

        prefs.edit().clear().apply()

        val restore = prefs.edit()
        if (preservedUrl != null) restore.putString(KEY_SERVER_URL, preservedUrl)
        if (preservedUrlSig != null) restore.putString(KEY_SERVER_URL_SIG, preservedUrlSig)
        if (preservedInstallId != null) restore.putString(KEY_INSTALL_ID, preservedInstallId)
        if (preservedInstallSecret != null) restore.putString(KEY_INSTALL_SECRET, preservedInstallSecret)
        restore.apply()

        _authCleared.tryEmit(Unit)
    }

    fun saveUser(
        token: String,
        refreshToken: String?,
        id: Long,
        username: String,
        firstName: String?,
        lastName: String?,
        role: String,
    ) {
        prefs.edit()
            .putString(KEY_ACCESS_TOKEN, token)
            .putString(KEY_REFRESH_TOKEN, refreshToken)
            .putLong(KEY_USER_ID, id)
            .putString(KEY_USERNAME, username)
            .putString(KEY_USER_FIRST_NAME, firstName)
            .putString(KEY_USER_LAST_NAME, lastName)
            .putString(KEY_USER_ROLE, role)
            .apply()
    }

    private companion object {
        private const val KEY_ACCESS_TOKEN = "access_token"
        private const val KEY_REFRESH_TOKEN = "refresh_token"
        private const val KEY_USER_ID = "user_id"
        private const val KEY_USERNAME = "username"
        private const val KEY_USER_ROLE = "user_role"
        private const val KEY_USER_FIRST_NAME = "user_first_name"
        private const val KEY_USER_LAST_NAME = "user_last_name"
        private const val KEY_STORE_NAME = "store_name"
        private const val KEY_SERVER_URL = "server_url"
        private const val KEY_SERVER_URL_SIG = "server_url_sig"
        private const val KEY_INSTALL_SECRET = "install_hmac_secret"
        private const val KEY_INSTALL_ID = "install_id"

        private const val HMAC_ALGORITHM = "HmacSHA256"
        private const val INSTALL_SECRET_BYTES = 32
    }
}
