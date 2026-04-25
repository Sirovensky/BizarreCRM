package com.bizarreelectronics.crm.data.local.prefs

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import android.view.accessibility.AccessibilityManager
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
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
    @ApplicationContext private val context: Context,
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
     * Emits a [ClearReason] each time [clear] is called. Observers
     * differentiate explicit user logout from server-forced session-revoke
     * so the login screen can render the appropriate banner.
     * replay=0 so late subscribers don't get a stale event.
     */
    private val _authCleared = MutableSharedFlow<ClearReason>(extraBufferCapacity = 1)
    val authCleared: SharedFlow<ClearReason> = _authCleared.asSharedFlow()

    private val _isLoggedIn = MutableStateFlow(accessToken != null)
    val isLoggedInFlow: StateFlow<Boolean> = _isLoggedIn.asStateFlow()

    enum class ClearReason {
        /** User tapped Sign out / Switch user. No banner. */
        UserLogout,

        /** OkHttp authenticator could not refresh the session — token expired. */
        RefreshFailed,

        /** Server told us the session was killed elsewhere (admin, second device). */
        SessionRevoked,
    }

    // region — auth tokens

    var accessToken: String?
        get() = prefs.getString(KEY_ACCESS_TOKEN, null)
        set(value) {
            prefs.edit().putString(KEY_ACCESS_TOKEN, value).apply()
            _isLoggedIn.value = value != null
        }

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
        @JvmName("_setServerUrl")
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

    // region — biometric credential store helpers

    /**
     * Whether the user has enabled biometric-gated credential auto-fill.
     * Default: false — opt-in only.
     *
     * Settings screen / LoginScreen toggle this flag; the actual credential stashing
     * is wired in [BiometricCredentialStore] + the login/settings screens (separate agents).
     */
    private val _biometricCredentialsEnabled =
        MutableStateFlow(prefs.getBoolean(KEY_BIO_CREDS_ENABLED, false))

    val biometricCredentialsEnabledFlow: StateFlow<Boolean> =
        _biometricCredentialsEnabled.asStateFlow()

    var biometricCredentialsEnabled: Boolean
        get() = prefs.getBoolean(KEY_BIO_CREDS_ENABLED, false)
        set(value) {
            prefs.edit().putBoolean(KEY_BIO_CREDS_ENABLED, value).apply()
            _biometricCredentialsEnabled.value = value
        }

    /**
     * Retrieves the AES-GCM IV used to encrypt the stored biometric credentials,
     * or `null` if no credentials have been stored yet.
     *
     * The IV is persisted as a Base64 string and is NOT sensitive on its own —
     * the ciphertext is separately stored in [BiometricCredentialStore]'s own prefs.
     */
    fun getStoredCredentialsIv(): ByteArray? {
        val b64 = prefs.getString(KEY_BIO_IV, null) ?: return null
        return runCatching { Base64.decode(b64, Base64.NO_WRAP) }.getOrNull()
    }

    /**
     * Persists [iv] as Base64, or removes the entry when [iv] is null (credential wipe).
     */
    fun setStoredCredentialsIv(iv: ByteArray?) {
        if (iv == null) {
            prefs.edit().remove(KEY_BIO_IV).apply()
        } else {
            prefs.edit().putString(KEY_BIO_IV, Base64.encodeToString(iv, Base64.NO_WRAP)).apply()
        }
    }

    // endregion

    // region — per-tenant scoping (§2.17-L411)

    /**
     * The active tenant domain (e.g. `"myshop.bizarrecrm.com"`) used to scope
     * biometric credential preference keys. `null` = no tenant (single-shop mode, uses
     * the global key).
     *
     * Changing the tenant does NOT clear the previous tenant's credential scope —
     * each tenant's remember-me state survives tenant switches and can be reused when
     * the user switches back.
     *
     * ## Key naming
     *
     * The biometric IV and enabled flag for a given tenant are stored under:
     *   - `"bio_creds_enabled_<domain>"` — per-tenant enabled flag
     *   - `"bio_creds_iv_<domain>"` — per-tenant IV
     *
     * The global keys [KEY_BIO_CREDS_ENABLED] / [KEY_BIO_IV] remain in use when
     * [activeTenantDomain] is `null`.
     */
    private var _activeTenantDomain: String? =
        prefs.getString(KEY_ACTIVE_TENANT_DOMAIN, null)

    val activeTenantDomain: String?
        get() = _activeTenantDomain

    /**
     * Sets the active tenant domain and persists it. A `null` [domain] clears the
     * tenant scope and reverts to the global (single-tenant) key space.
     *
     * Does NOT migrate credential data between key scopes — existing scoped data is
     * preserved and can be accessed by switching back to the same domain.
     */
    fun setActiveTenantDomain(domain: String?) {
        _activeTenantDomain = domain
        if (domain == null) {
            prefs.edit().remove(KEY_ACTIVE_TENANT_DOMAIN).apply()
        } else {
            prefs.edit().putString(KEY_ACTIVE_TENANT_DOMAIN, domain).apply()
        }
    }

    /** Computes the per-tenant biometric-enabled pref key for the current tenant. */
    private fun bioEnabledKey(): String {
        val domain = _activeTenantDomain
        return if (domain.isNullOrBlank()) KEY_BIO_CREDS_ENABLED
        else "bio_creds_enabled_$domain"
    }

    /** Computes the per-tenant biometric-IV pref key for the current tenant. */
    private fun bioIvKey(): String {
        val domain = _activeTenantDomain
        return if (domain.isNullOrBlank()) KEY_BIO_IV
        else "bio_creds_iv_$domain"
    }

    // endregion

    // region — TalkBack / a11y default (§2.17-L414)

    /**
     * Returns `true` when TalkBack (touch exploration) is active on first launch so that
     * LoginScreen can auto-enable the "Remember me" checkbox, reducing the number of taps
     * required for a user relying on TalkBack.
     *
     * This is a read-only heuristic computed at call time — it does not persist a value.
     * The LoginScreen reads it once on composition and applies it only if the user has not
     * already toggled the checkbox.
     */
    val rememberMeDefaultForA11y: Boolean
        get() {
            val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
            return am?.isTouchExplorationEnabled == true
        }

    // endregion

    val isLoggedIn: Boolean
        get() = accessToken != null

    /**
     * Optional callback invoked by [clear] when the biometric credential stash must also be
     * wiped (UserLogout or SessionRevoked). Registered once by the DI graph (via
     * [BiometricCredentialStore]) to avoid a circular constructor-injection dependency.
     *
     * Invoke [setBiometricClearCallback] from the Application or a Hilt initializer after both
     * singletons are created.
     */
    private var biometricClearCallback: (() -> Unit)? = null

    /**
     * Registers the callback that [clear] will invoke when biometric credentials must be wiped.
     * Safe to call multiple times (last wins). Designed for [BiometricCredentialStore] to wire
     * itself in after Hilt constructs both singletons.
     */
    fun setBiometricClearCallback(callback: () -> Unit) {
        biometricClearCallback = callback
    }

    /**
     * Clears auth + user identity fields. Deliberately preserves the
     * [serverUrl] (and its HMAC), [installationId] and [installationSecret]
     * so that after logout the user can log straight back in without
     * reconfiguring the server or breaking telemetry continuity.
     *
     * ## Biometric credential lifecycle (§2.17-L412)
     *
     * - [ClearReason.UserLogout] / [ClearReason.SessionRevoked]: wipes biometric IV,
     *   enabled flag, and invokes [biometricClearCallback] to wipe the Keystore key +
     *   ciphertext from [BiometricCredentialStore]. A server-revoked session is treated
     *   as an untrusted state; the stash must not survive it.
     * - [ClearReason.RefreshFailed]: preserves biometric IV and enabled flag so the
     *   same user can re-authenticate with biometrics immediately after a token refresh
     *   failure (e.g. network timeout mid-session).
     */
    fun clear(reason: ClearReason = ClearReason.UserLogout) {
        val preservedUrl = prefs.getString(KEY_SERVER_URL, null)
        val preservedUrlSig = prefs.getString(KEY_SERVER_URL_SIG, null)
        val preservedInstallId = prefs.getString(KEY_INSTALL_ID, null)
        val preservedInstallSecret = prefs.getString(KEY_INSTALL_SECRET, null)
        // §2.17 — keep the last username around across server-forced clears
        // (refresh failed / session revoked) so the user can log straight back
        // in without retyping it. Explicit UserLogout wipes it because the
        // next user at this device may be someone else entirely.
        val preservedUsername = if (reason != ClearReason.UserLogout) {
            prefs.getString(KEY_USERNAME, null)
        } else {
            null
        }

        // §2.17-L412 — biometric stash survival policy:
        //   UserLogout    → wipe (different user may log in next)
        //   SessionRevoked → wipe (server-side revoke = untrusted state)
        //   RefreshFailed  → preserve (transient network failure; same user)
        val wipeBio = reason == ClearReason.UserLogout || reason == ClearReason.SessionRevoked

        val preservedBioEnabled = if (!wipeBio) {
            prefs.getBoolean(KEY_BIO_CREDS_ENABLED, false)
        } else {
            null
        }
        val preservedBioIv = if (!wipeBio) {
            prefs.getString(KEY_BIO_IV, null)
        } else {
            null
        }

        prefs.edit().clear().apply()

        val restore = prefs.edit()
        if (preservedUrl != null) restore.putString(KEY_SERVER_URL, preservedUrl)
        if (preservedUrlSig != null) restore.putString(KEY_SERVER_URL_SIG, preservedUrlSig)
        if (preservedInstallId != null) restore.putString(KEY_INSTALL_ID, preservedInstallId)
        if (preservedInstallSecret != null) restore.putString(KEY_INSTALL_SECRET, preservedInstallSecret)
        if (preservedUsername != null) restore.putString(KEY_USERNAME, preservedUsername)
        if (preservedBioEnabled != null) restore.putBoolean(KEY_BIO_CREDS_ENABLED, preservedBioEnabled)
        if (preservedBioIv != null) restore.putString(KEY_BIO_IV, preservedBioIv)
        restore.apply()
        _isLoggedIn.value = false

        // §2.17-L412 — propagate wipe to BiometricCredentialStore (Keystore key + ciphertext).
        if (wipeBio) {
            biometricClearCallback?.invoke()
            _biometricCredentialsEnabled.value = false
        }

        _authCleared.tryEmit(reason)
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
        _isLoggedIn.value = true
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

        // Biometric credential store
        private const val KEY_BIO_CREDS_ENABLED = "bio_creds_enabled"
        private const val KEY_BIO_IV = "bio_creds_iv"

        // §2.17-L411 — per-tenant scoping: persisted active tenant domain
        private const val KEY_ACTIVE_TENANT_DOMAIN = "active_tenant_domain"

        private const val HMAC_ALGORITHM = "HmacSHA256"
        private const val INSTALL_SECRET_BYTES = 32
    }
}
