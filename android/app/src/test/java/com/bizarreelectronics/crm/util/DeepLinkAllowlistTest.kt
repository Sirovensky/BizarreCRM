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
}
