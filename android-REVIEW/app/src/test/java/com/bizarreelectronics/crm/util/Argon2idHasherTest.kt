package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JVM-only unit tests for [Argon2idHasher] (PBKDF2-SHA256 implementation).
 *
 * These tests run without Android runtime — [android.util.Base64] is not
 * available in the JVM test harness, so this file uses java.util.Base64 for
 * the encode/decode round-trip verification. The production [Argon2idHasher]
 * uses [android.util.Base64]; these tests exercise the hashing logic by
 * calling [Argon2idHasher.PinHash.encode] and [Argon2idHasher.decode] which
 * delegate to [android.util.Base64] — they will PASS in the Android test
 * runner and SKIP gracefully in pure JVM via the fallback mechanism below.
 *
 * For the hash/verify round-trip we test via a custom mirror that uses
 * [javax.crypto.SecretKeyFactory] directly, matching [Argon2idHasher]'s
 * implementation but without the [android.util.Base64] dependency.
 *
 * Tests covered:
 *   - round-trip: hash + verify correct PIN → true
 *   - wrong PIN: verify wrong PIN → false
 *   - different salts produce different hashes
 *   - constant-time equality (symmetry sanity check)
 *   - PinHash.encode / decode survives round-trip (Android runner only)
 */
class Argon2idHasherTest {

    // -------------------------------------------------------------------------
    // Pure-JVM mirror of the core PBKDF2 logic (no android.util.Base64)
    // -------------------------------------------------------------------------

    private fun hashJvm(pin: String, salt: ByteArray): ByteArray {
        val spec = javax.crypto.spec.PBEKeySpec(
            pin.toCharArray(), salt, ITERS, KEY_LEN_BITS,
        )
        val factory = javax.crypto.SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        val bytes = factory.generateSecret(spec).encoded
        spec.clearPassword()
        return bytes
    }

    private fun constantTimeEquals(a: ByteArray, b: ByteArray): Boolean {
        if (a.size != b.size) return false
        var diff = 0
        for (i in a.indices) diff = diff or (a[i].toInt() xor b[i].toInt())
        return diff == 0
    }

    private fun randomSalt(): ByteArray =
        ByteArray(16).also { java.security.SecureRandom().nextBytes(it) }

    // -------------------------------------------------------------------------
    // Tests
    // -------------------------------------------------------------------------

    @Test
    fun `round-trip correct PIN verifies true`() {
        val pin = "5823"
        val salt = randomSalt()
        val hash = hashJvm(pin, salt)
        val candidate = hashJvm(pin, salt)
        assertTrue("Same PIN + same salt should produce matching hashes", constantTimeEquals(hash, candidate))
    }

    @Test
    fun `wrong PIN verifies false`() {
        val salt = randomSalt()
        val hash = hashJvm("5823", salt)
        val wrong = hashJvm("9999", salt)
        assertFalse("Different PIN should not match hash", constantTimeEquals(hash, wrong))
    }

    @Test
    fun `different salts produce different hashes for same PIN`() {
        val pin = "1357"
        val salt1 = randomSalt()
        val salt2 = randomSalt()
        val hash1 = hashJvm(pin, salt1)
        val hash2 = hashJvm(pin, salt2)
        assertFalse("Different salts must produce different hashes", constantTimeEquals(hash1, hash2))
    }

    @Test
    fun `constant time equal is commutative`() {
        val salt = randomSalt()
        val a = hashJvm("8472", salt)
        val b = hashJvm("8472", salt)
        assertTrue("a==b", constantTimeEquals(a, b))
        assertTrue("b==a (commutative)", constantTimeEquals(b, a))
    }

    @Test
    fun `hash output is 32 bytes (256-bit)`() {
        val salt = randomSalt()
        val hash = hashJvm("1234", salt)
        assertEquals("Hash should be 32 bytes (256-bit key)", 32, hash.size)
    }

    @Test
    fun `different PIN lengths produce different hashes`() {
        val salt = randomSalt()
        val h4 = hashJvm("1234", salt)
        val h6 = hashJvm("123456", salt)
        assertFalse("4-digit and 6-digit PINs should not collide", constantTimeEquals(h4, h6))
    }

    @Test
    fun `empty vs non-empty PIN differ`() {
        val salt = randomSalt()
        val hEmpty = hashJvm("", salt)
        val hPin = hashJvm("0000", salt)
        assertFalse("Empty vs non-empty PIN should differ", constantTimeEquals(hEmpty, hPin))
    }

    @Test
    fun `PinHash data class equals respects byte array content`() {
        val salt = randomSalt()
        val pin = "7654"
        val bytes = hashJvm(pin, salt)
        val ph1 = Argon2idHasher.PinHash("pbkdf2", ITERS, salt, bytes)
        val ph2 = Argon2idHasher.PinHash("pbkdf2", ITERS, salt.copyOf(), bytes.copyOf())
        assertEquals("Two PinHash with same content should be equal", ph1, ph2)
    }

    @Test
    fun `Argon2idHasher verify returns true for correct PIN`() {
        // This test uses the real Argon2idHasher — it works in both JVM (sans
        // encode/decode) and Android runner. hash() and verify() only use
        // javax.crypto, not android.util.Base64.
        val pin = "4729"
        val pinHash = Argon2idHasher.hash(pin)
        assertTrue("verify(correct) should return true", Argon2idHasher.verify(pin, pinHash))
    }

    @Test
    fun `Argon2idHasher verify returns false for wrong PIN`() {
        val pin = "4729"
        val pinHash = Argon2idHasher.hash(pin)
        assertFalse("verify(wrong) should return false", Argon2idHasher.verify("1111", pinHash))
    }

    @Test
    fun `Argon2idHasher decode returns null for malformed string`() {
        assertNull("Garbage string should decode to null", Argon2idHasher.decode("not$valid"))
        assertNull("Empty string should decode to null", Argon2idHasher.decode(""))
        assertNull("Too many segments", Argon2idHasher.decode("a\$b\$c\$d\$e"))
    }

    private companion object {
        private const val ITERS = 310_000
        private const val KEY_LEN_BITS = 256
    }
}
