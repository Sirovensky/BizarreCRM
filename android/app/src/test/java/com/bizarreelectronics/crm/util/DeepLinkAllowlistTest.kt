package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * §31.1 — unit coverage for §13.2 / §68.3 deep-link allowlist.
 */
class DeepLinkAllowlistTest {

    @Test fun `allowed routes pass through`() {
        assertEquals("ticket/new", DeepLinkAllowlist.resolve("ticket/new"))
        assertEquals("customer/new", DeepLinkAllowlist.resolve("customer/new"))
        assertEquals("scan", DeepLinkAllowlist.resolve("scan"))
    }

    @Test fun `unknown routes are dropped`() {
        assertNull(DeepLinkAllowlist.resolve("tickets"))
        assertNull(DeepLinkAllowlist.resolve("../admin"))
        assertNull(DeepLinkAllowlist.resolve("ticket/../../etc/passwd"))
    }

    @Test fun `blank or null is dropped`() {
        assertNull(DeepLinkAllowlist.resolve(null))
        assertNull(DeepLinkAllowlist.resolve(""))
        assertNull(DeepLinkAllowlist.resolve("   "))
    }

    @Test fun `routes set is non-empty`() {
        // Defensive: if a refactor accidentally empties the allowlist, every
        // deep-link would silently drop. Fail loud here so the diff review
        // catches the regression.
        assertTrue(DeepLinkAllowlist.routes.isNotEmpty())
    }

    // §2.7 L330 — setup token deep-link tests

    @Test fun `valid setup token is extracted and returns login route`() {
        val token = "abcdefghij1234567890"          // exactly 20 chars — minimum
        val result = DeepLinkAllowlist.resolve("setup/$token")
        assertEquals("login?setupToken=$token", result)
    }

    @Test fun `long valid setup token is accepted`() {
        val token = "A".repeat(128)                 // maximum 128 chars
        val result = DeepLinkAllowlist.resolve("setup/$token")
        assertEquals("login?setupToken=$token", result)
    }

    @Test fun `setup token with URL-safe chars is accepted`() {
        val token = "Az09_-Az09_-Az09_-Az09_-Az09_-Az0" // alphanumeric + _ + -
        val result = DeepLinkAllowlist.resolve("setup/$token")
        // token length = 33 ≥ 20; should pass
        assertEquals("login?setupToken=$token", result)
    }

    @Test fun `setup token that is too short is rejected`() {
        val shortToken = "abc1234"                  // 7 chars < 20
        assertNull(DeepLinkAllowlist.resolve("setup/$shortToken"))
    }

    @Test fun `setup token that is too long is rejected`() {
        val longToken = "A".repeat(129)             // 129 chars > 128
        assertNull(DeepLinkAllowlist.resolve("setup/$longToken"))
    }

    @Test fun `setup token with slash is rejected`() {
        // A slash inside the token string could signal path traversal
        assertNull(DeepLinkAllowlist.resolve("setup/abc1234567890123456/extra"))
    }

    @Test fun `setup token with special characters is rejected`() {
        // Characters outside [A-Za-z0-9_-] must be rejected
        val badToken = "abcdefghij1234567890!@#$"
        assertNull(DeepLinkAllowlist.resolve("setup/$badToken"))
    }

    @Test fun `empty setup token is rejected`() {
        assertNull(DeepLinkAllowlist.resolve("setup/"))
    }

    @Test fun `bare setup host without token is rejected`() {
        // "setup" with no slash and no token
        assertNull(DeepLinkAllowlist.resolve("setup"))
    }

    @Test fun `validateSetupToken returns token for valid input`() {
        val token = "abcdefghij1234567890"
        assertEquals(token, DeepLinkAllowlist.validateSetupToken(token))
    }

    @Test fun `validateSetupToken returns null for blank input`() {
        assertNull(DeepLinkAllowlist.validateSetupToken(null))
        assertNull(DeepLinkAllowlist.validateSetupToken(""))
        assertNull(DeepLinkAllowlist.validateSetupToken("   "))
    }

    @Test fun `validateSetupToken returns null for invalid chars`() {
        assertNull(DeepLinkAllowlist.validateSetupToken("abc/../etc"))
        assertNull(DeepLinkAllowlist.validateSetupToken("short"))
    }
}
