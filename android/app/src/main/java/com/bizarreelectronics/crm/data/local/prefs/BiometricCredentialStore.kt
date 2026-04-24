package com.bizarreelectronics.crm.data.local.prefs

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Encrypted storage for login credentials, protected by a biometric-gated Android Keystore key.
 *
 * ## Keystore contract
 *
 * The AES-256-GCM key alias [KEY_ALIAS] is created with:
 *  - [KeyProperties.PURPOSE_ENCRYPT] | [KeyProperties.PURPOSE_DECRYPT]
 *  - `setUserAuthenticationRequired(true)` — the key cannot be used without a fresh biometric
 *    authentication. The system enforces this; no user-space token is needed.
 *  - `setInvalidatedByBiometricEnrollment(true)` — if the user adds a new fingerprint / face or
 *    wipes all biometrics, the key is permanently destroyed and any stored ciphertext becomes
 *    unreadable. [retrieve] handles [KeyPermanentlyInvalidatedException] gracefully by returning
 *    [RetrieveResult.Invalidated] so the caller can prompt for a fresh password-based login and
 *    re-stash the credentials.
 *  - `setInvalidatedByBiometricEnrollment` is paired with `setUserAuthenticationRequired` as per
 *    Android docs — both are required for the strongest credential binding guarantee.
 *
 * ## Why `setUserAuthenticationRequired(true)`
 *
 * Without this flag the Keystore key could be used by any code running in the app process at any
 * time, defeating the purpose of gating credential retrieval behind biometry. With the flag, the
 * OS guarantees that the Cipher can only be initialised after a successful BiometricPrompt
 * authentication with a CryptoObject wrapping that Cipher. This means the plaintext password
 * never exists in memory unless the user has *just* proven who they are.
 *
 * ## Thread safety
 *
 * Keystore and SharedPreferences operations are I/O-bound. All suspending functions dispatch to
 * [Dispatchers.IO] internally; callers need not switch dispatchers.
 *
 * ## Logging invariant
 *
 * No credential material (username, password, ciphertext) is ever written to Logcat. This is a
 * hard invariant: any future modification MUST preserve it.
 */
@Singleton
class BiometricCredentialStore @Inject constructor(
    @ApplicationContext private val context: Context,
) {

    // region — EncryptedSharedPreferences (for IV + ciphertext)

    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs by lazy {
        EncryptedSharedPreferences.create(
            context,
            PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    // endregion

    // region — Keystore key management

    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).also { it.load(null) }
        keyStore.getKey(KEY_ALIAS, null)?.let { return it as SecretKey }

        val keyGen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(KEY_SIZE_BITS)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
            .build()
        keyGen.init(spec)
        return keyGen.generateKey()
    }

    // endregion

    // region — Public API

    /**
     * Whether ciphertext is currently stored. Does NOT guarantee the Keystore key still
     * exists — call [retrieve] to learn that authoritatively.
     */
    val hasStoredCredentials: Boolean
        get() = prefs.contains(KEY_CIPHERTEXT) && prefs.contains(KEY_IV)

    /**
     * Encrypts [username] + [password] as a JSON tuple using [cipher] (must be initialised in
     * ENCRYPT_MODE with the biometric-gated Keystore key via [BiometricAuth.encryptWithBiometric])
     * and persists the resulting IV + ciphertext to [EncryptedSharedPreferences].
     *
     * Returns `true` on success, `false` on any crypto / I/O failure.
     *
     * The raw password is never written to Logcat.
     */
    suspend fun store(username: String, password: String, cipher: Cipher): Boolean =
        withContext(Dispatchers.IO) {
            runCatching {
                val payload = JSONObject().put(JSON_USER, username).put(JSON_PASS, password)
                    .toString().toByteArray(Charsets.UTF_8)
                val ciphertext = cipher.doFinal(payload)
                val iv = cipher.iv

                prefs.edit()
                    .putString(KEY_IV, Base64.encodeToString(iv, Base64.NO_WRAP))
                    .putString(KEY_CIPHERTEXT, Base64.encodeToString(ciphertext, Base64.NO_WRAP))
                    .apply()
                true
            }.getOrElse { false }
        }

    /**
     * Decrypts the stored credentials using [cipher] (must be initialised in DECRYPT_MODE via
     * [BiometricAuth.decryptWithBiometric]).
     *
     * Returns a typed [RetrieveResult]:
     *  - [RetrieveResult.Success] — credentials decrypted OK.
     *  - [RetrieveResult.Absent] — nothing stored yet.
     *  - [RetrieveResult.Invalidated] — the Keystore key was permanently destroyed (new
     *    biometric enrolment). Caller should delete stored data and prompt for re-setup.
     *  - [RetrieveResult.Error] — transient failure; caller may retry or fall back.
     */
    suspend fun retrieve(cipher: Cipher): RetrieveResult =
        withContext(Dispatchers.IO) {
            val ivB64 = prefs.getString(KEY_IV, null)
            val ctB64 = prefs.getString(KEY_CIPHERTEXT, null)
            if (ivB64 == null || ctB64 == null) return@withContext RetrieveResult.Absent

            runCatching {
                val ciphertext = Base64.decode(ctB64, Base64.NO_WRAP)
                val plainBytes = cipher.doFinal(ciphertext)
                val json = JSONObject(String(plainBytes, Charsets.UTF_8))
                RetrieveResult.Success(
                    Credentials(
                        username = json.getString(JSON_USER),
                        password = json.getString(JSON_PASS),
                    ),
                )
            }.getOrElse { ex ->
                when (ex) {
                    is KeyPermanentlyInvalidatedException -> RetrieveResult.Invalidated
                    else -> RetrieveResult.Error(ex)
                }
            }
        }

    /**
     * Deletes the Keystore key alias and the stored IV/ciphertext. After this call
     * [hasStoredCredentials] returns false. Idempotent — safe to call even if nothing is stored.
     */
    fun clear() {
        runCatching {
            val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).also { it.load(null) }
            if (keyStore.containsAlias(KEY_ALIAS)) {
                keyStore.deleteEntry(KEY_ALIAS)
            }
        }
        prefs.edit().remove(KEY_IV).remove(KEY_CIPHERTEXT).apply()
    }

    /**
     * Returns a [Cipher] initialised in ENCRYPT_MODE with the biometric-gated Keystore key.
     * Intended to be passed to [BiometricAuth.encryptWithBiometric] as a [CryptoObject].
     */
    fun createEncryptCipher(): Cipher {
        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
        return cipher
    }

    /**
     * Returns a [Cipher] initialised in DECRYPT_MODE with the stored [iv].
     * Intended to be passed to [BiometricAuth.decryptWithBiometric] as a [CryptoObject].
     */
    fun createDecryptCipher(iv: ByteArray): Cipher {
        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        val spec = GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv)
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).also { it.load(null) }
        val key = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
            ?: error("Keystore key '$KEY_ALIAS' not found — call createEncryptCipher first")
        cipher.init(Cipher.DECRYPT_MODE, key, spec)
        return cipher
    }

    // endregion

    // region — Data types

    /** Successful decryption result carrying the decrypted credentials. */
    data class Credentials(val username: String, val password: String)

    /** Typed result for [retrieve] — never throws. */
    sealed class RetrieveResult {
        data class Success(val credentials: Credentials) : RetrieveResult()
        data object Absent : RetrieveResult()

        /**
         * The Keystore key was permanently invalidated (new biometric enrolment or wipe).
         * Caller MUST call [clear] and prompt the user to re-enable biometric login.
         */
        data object Invalidated : RetrieveResult()
        data class Error(val cause: Throwable) : RetrieveResult()
    }

    // endregion

    private companion object {
        private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        private const val KEY_ALIAS = "biometric_creds_v1"
        private const val KEY_SIZE_BITS = 256
        private const val CIPHER_TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_LENGTH_BITS = 128
        private const val PREFS_NAME = "biometric_cred_prefs"
        private const val KEY_IV = "bio_iv"
        private const val KEY_CIPHERTEXT = "bio_ct"
        private const val JSON_USER = "u"
        private const val JSON_PASS = "p"
    }
}
