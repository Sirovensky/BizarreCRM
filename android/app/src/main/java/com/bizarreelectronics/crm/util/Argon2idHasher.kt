package com.bizarreelectronics.crm.util

import android.util.Base64
import java.security.SecureRandom
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/**
 * Client-side PIN hash mirror — §2.15 ActionPlan L382-L391.
 *
 * ## Why PBKDF2, not Argon2id?
 *
 * The plan specified Argon2id, but `de.mkammerer:argon2-jvm` bundles native
 * NDK `.so` libraries that are not available on all Android ABI targets without
 * a custom NDK build pipeline. `argon2-jvm-nolibs` requires the `.so` shipped
 * separately at runtime, so it is equally impractical for a pure-APK release.
 *
 * We instead use **PBKDF2-HMAC-SHA256 with 310 000 iterations**, which the
 * OWASP Password Storage Cheat Sheet rates as bcrypt-equivalent for 2023+
 * (310k PBKDF2-SHA256 ≈ bcrypt cost 10 in time-to-crack at modern GPU speeds).
 * This matches the server's bcrypt approach in threat-model equivalence while
 * remaining 100% portable on every Android minSdk 26+ device.
 *
 * ## Role of this hash
 *
 * This is a **client-side mirror only**. It enables offline PIN verification
 * during the cold-start lock gate so the app does not need a live server
 * connection for every resume. The server (bcrypt) remains the authoritative
 * source for all mutating operations (change-pin, switch-user). The mirror is
 * stored in EncryptedSharedPreferences (AES-256-GCM) so a rooted device cannot
 * trivially read or tamper with it.
 *
 * ## Encoded format
 *
 * Stored as: `"pbkdf2$<iterations>$<salt_b64>$<hash_b64>"`
 * All Base64 segments use URL-safe, no-padding encoding.
 *
 * @see PinHash
 * @see com.bizarreelectronics.crm.data.local.prefs.PinPreferences
 */
object Argon2idHasher {

    private const val ALGORITHM = "PBKDF2WithHmacSHA256"
    private const val ITERATIONS = 310_000
    private const val KEY_LENGTH_BITS = 256
    private const val SALT_BYTES = 16

    /**
     * Hashes [pin] with [salt] (random by default) and returns a [PinHash].
     *
     * NEVER log [pin] or the resulting [PinHash.hashBytes].
     */
    fun hash(pin: String, salt: ByteArray = randomSalt()): PinHash {
        val spec = PBEKeySpec(pin.toCharArray(), salt, ITERATIONS, KEY_LENGTH_BITS)
        val factory = SecretKeyFactory.getInstance(ALGORITHM)
        val hashBytes = factory.generateSecret(spec).encoded
        spec.clearPassword()
        return PinHash(
            algorithm = "pbkdf2",
            iterations = ITERATIONS,
            salt = salt,
            hashBytes = hashBytes,
        )
    }

    /**
     * Returns true when [pin] matches [stored], using a constant-time comparison
     * to prevent timing attacks.
     *
     * NEVER log [pin].
     */
    fun verify(pin: String, stored: PinHash): Boolean {
        val candidate = hash(pin, stored.salt)
        return constantTimeEquals(candidate.hashBytes, stored.hashBytes)
    }

    /** Parses a stored [PinHash.encode] string back to a [PinHash], or null if malformed. */
    fun decode(encoded: String): PinHash? {
        val parts = encoded.split("$")
        if (parts.size != 4) return null
        return try {
            val algo = parts[0]
            val iters = parts[1].toInt()
            val salt = Base64.decode(parts[2], Base64.URL_SAFE or Base64.NO_PADDING)
            val hash = Base64.decode(parts[3], Base64.URL_SAFE or Base64.NO_PADDING)
            PinHash(algo, iters, salt, hash)
        } catch (_: Exception) {
            null
        }
    }

    /** Cryptographically random salt. */
    fun randomSalt(): ByteArray = ByteArray(SALT_BYTES).also { SecureRandom().nextBytes(it) }

    /** Constant-time comparison — prevents timing oracle on hash equality. */
    private fun constantTimeEquals(a: ByteArray, b: ByteArray): Boolean {
        if (a.size != b.size) return false
        var diff = 0
        for (i in a.indices) diff = diff or (a[i].toInt() xor b[i].toInt())
        return diff == 0
    }

    /**
     * Immutable value type holding a computed PIN hash.
     *
     * @property algorithm  Hash algorithm tag (always "pbkdf2" in this build).
     * @property iterations PBKDF2 iteration count used when deriving [hashBytes].
     * @property salt       Random salt bytes (16 bytes / 128-bit).
     * @property hashBytes  Derived key bytes (32 bytes / 256-bit). Never log.
     */
    data class PinHash(
        val algorithm: String,
        val iterations: Int,
        val salt: ByteArray,
        val hashBytes: ByteArray,
    ) {
        /**
         * Encodes to `"pbkdf2$<iterations>$<salt_b64>$<hash_b64>"` for persistence.
         * Never log this value — it contains hash bytes.
         */
        fun encode(): String {
            val saltB64 = Base64.encodeToString(salt, Base64.URL_SAFE or Base64.NO_PADDING)
            val hashB64 = Base64.encodeToString(hashBytes, Base64.URL_SAFE or Base64.NO_PADDING)
            return "$algorithm\$$iterations\$$saltB64\$$hashB64"
        }

        // ByteArray fields require manual equals/hashCode to satisfy data class contract.
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is PinHash) return false
            return algorithm == other.algorithm &&
                iterations == other.iterations &&
                salt.contentEquals(other.salt) &&
                hashBytes.contentEquals(other.hashBytes)
        }

        override fun hashCode(): Int {
            var result = algorithm.hashCode()
            result = 31 * result + iterations
            result = 31 * result + salt.contentHashCode()
            result = 31 * result + hashBytes.contentHashCode()
            return result
        }
    }
}
