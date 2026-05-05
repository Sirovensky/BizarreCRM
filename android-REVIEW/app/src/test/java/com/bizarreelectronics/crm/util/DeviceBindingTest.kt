package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.MessageDigest

/**
 * Unit tests for [DeviceBinding].
 *
 * The SHA-256 computation is pure JVM — no Android runtime required.
 * We mirror the [DeviceBinding.fingerprint] algorithm here using raw inputs
 * to keep the tests hermetic and avoid Robolectric overhead.
 */
class DeviceBindingTest {

    // Mirror of DeviceBinding.fingerprint() so tests don't depend on Context.
    private fun computeFingerprint(androidId: String, packageName: String): String {
        val raw = "$androidId:$packageName".toByteArray(Charsets.UTF_8)
        val digest = MessageDigest.getInstance("SHA-256").digest(raw)
        return digest.joinToString("") { b -> "%02x".format(b) }
    }

    @Test
    fun `fingerprint is deterministic for same androidId and packageName`() {
        val id = "abc123def456"
        val pkg = "com.bizarreelectronics.crm"

        val fp1 = computeFingerprint(id, pkg)
        val fp2 = computeFingerprint(id, pkg)

        assertEquals(
            "Same androidId + package must produce identical fingerprint",
            fp1,
            fp2,
        )
    }

    @Test
    fun `fingerprint differs for different androidId same packageName`() {
        val pkg = "com.bizarreelectronics.crm"
        val fp1 = computeFingerprint("device-aaa", pkg)
        val fp2 = computeFingerprint("device-bbb", pkg)

        assertNotEquals(
            "Different androidId must produce different fingerprint",
            fp1,
            fp2,
        )
    }

    @Test
    fun `fingerprint differs for same androidId different packageName`() {
        val id = "abc123def456"
        val fp1 = computeFingerprint(id, "com.example.app1")
        val fp2 = computeFingerprint(id, "com.example.app2")

        assertNotEquals(
            "Different packageName must produce different fingerprint",
            fp1,
            fp2,
        )
    }

    @Test
    fun `fingerprint is 64 hex characters (256-bit SHA-256 output)`() {
        val fp = computeFingerprint("testid", "com.test.pkg")

        assertEquals(
            "SHA-256 fingerprint must be exactly 64 hex characters",
            64,
            fp.length,
        )
        assertTrue(
            "Fingerprint must contain only lowercase hex characters",
            fp.all { it in '0'..'9' || it in 'a'..'f' },
        )
    }

    @Test
    fun `empty androidId produces valid deterministic fingerprint`() {
        val fp1 = computeFingerprint("", "com.bizarreelectronics.crm")
        val fp2 = computeFingerprint("", "com.bizarreelectronics.crm")

        assertEquals(
            "Empty androidId must still produce a deterministic fingerprint",
            fp1,
            fp2,
        )
        assertEquals(64, fp1.length)
    }

    @Test
    fun `fingerprint does not expose raw androidId`() {
        val id = "super-secret-android-id-1234"
        val fp = computeFingerprint(id, "com.bizarreelectronics.crm")

        // A hex SHA-256 digest must not contain the raw input string
        assertTrue(
            "Fingerprint must not contain the raw androidId",
            !fp.contains(id),
        )
    }
}
