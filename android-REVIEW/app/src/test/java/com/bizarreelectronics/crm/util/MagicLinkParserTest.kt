package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * §2.21 L454 — Unit tests for magic-link token parsing and validation.
 *
 * Exercises [DeepLinkAllowlist.validateMagicToken] and [DeepLinkAllowlist.resolve]
 * for the `magic/<token>` path. Pure JVM — no Android context required.
 *
 * Test inventory:
 *  1. Valid HTTPS App Link URI path segments → validated token returned.
 *  2. Valid custom-scheme candidate string → sentinel route returned.
 *  3. Token below minimum length (< 20 chars) → rejected.
 *  4. Token above maximum length (> 128 chars) → rejected.
 *  5. Token with disallowed characters (slash, space, special) → rejected.
 *  6. Null / blank token → rejected.
 *  7. Expired token stub: [validateMagicToken] is a shape-only check (server enforces
 *     TTL); client-side rejection is represented by asserting the token shape is valid
 *     while noting that server-side 410 handles true expiry.
 *  8. resolve("magic/<token>") returns sentinel "magic/<token>" for valid tokens.
 *  9. resolve("magic/") with missing token → null.
 * 10. resolve("magic/<invalid>") with bad token shape → null.
 */
class MagicLinkParserTest {

    // ── Minimum valid token: exactly 20 URL-safe base64 characters ────────────

    private val minToken = "AAAABBBBCCCCDDDDEEEE"          // 20 chars
    private val typicalToken = "abc123XYZ_-abc123XYZ_-abc"  // 25 chars, mixed case + symbols
    private val maxToken = "A".repeat(128)                   // 128 chars (boundary)

    // ── 1. validateMagicToken: valid tokens pass ───────────────────────────────

    @Test fun `validateMagicToken accepts minimum-length token`() {
        assertEquals(minToken, DeepLinkAllowlist.validateMagicToken(minToken))
    }

    @Test fun `validateMagicToken accepts typical token with URL-safe chars`() {
        assertEquals(typicalToken, DeepLinkAllowlist.validateMagicToken(typicalToken))
    }

    @Test fun `validateMagicToken accepts maximum-length token`() {
        assertEquals(maxToken, DeepLinkAllowlist.validateMagicToken(maxToken))
    }

    @Test fun `validateMagicToken returns non-null for valid 64-char hex token`() {
        // Hex strings (SHA-256 output shape) are a common token format.
        val hexToken = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        assertNotNull(DeepLinkAllowlist.validateMagicToken(hexToken))
    }

    // ── 2. validateMagicToken: invalid tokens rejected ────────────────────────

    @Test fun `validateMagicToken rejects token shorter than 20 chars`() {
        assertNull(DeepLinkAllowlist.validateMagicToken("tooshort123456789")) // 17 chars
        assertNull(DeepLinkAllowlist.validateMagicToken("A".repeat(19)))
    }

    @Test fun `validateMagicToken rejects token longer than 128 chars`() {
        assertNull(DeepLinkAllowlist.validateMagicToken("A".repeat(129)))
        assertNull(DeepLinkAllowlist.validateMagicToken("B".repeat(200)))
    }

    @Test fun `validateMagicToken rejects token containing a slash`() {
        // Path-traversal guard: slashes must not appear in token values.
        assertNull(DeepLinkAllowlist.validateMagicToken("abc/def123456789012"))
        assertNull(DeepLinkAllowlist.validateMagicToken("abc/../admin123456789"))
    }

    @Test fun `validateMagicToken rejects token containing spaces`() {
        assertNull(DeepLinkAllowlist.validateMagicToken("abc def123456789012"))
    }

    @Test fun `validateMagicToken rejects token containing special characters`() {
        assertNull(DeepLinkAllowlist.validateMagicToken("abc+def123456789012")) // + not URL-safe base64
        assertNull(DeepLinkAllowlist.validateMagicToken("abc=def123456789012")) // = not in URL-safe
        assertNull(DeepLinkAllowlist.validateMagicToken("abc@def123456789012"))
    }

    @Test fun `validateMagicToken rejects null`() {
        assertNull(DeepLinkAllowlist.validateMagicToken(null))
    }

    @Test fun `validateMagicToken rejects blank string`() {
        assertNull(DeepLinkAllowlist.validateMagicToken(""))
        assertNull(DeepLinkAllowlist.validateMagicToken("   "))
    }

    // ── 3. resolve: magic/<token> candidate ───────────────────────────────────

    @Test fun `resolve returns sentinel for valid magic-link candidate`() {
        val candidate = "magic/$typicalToken"
        assertEquals(candidate, DeepLinkAllowlist.resolve(candidate))
    }

    @Test fun `resolve returns sentinel for minimum-length magic token`() {
        val candidate = "magic/$minToken"
        assertEquals(candidate, DeepLinkAllowlist.resolve(candidate))
    }

    @Test fun `resolve returns null for magic prefix with missing token`() {
        assertNull(DeepLinkAllowlist.resolve("magic/"))
        assertNull(DeepLinkAllowlist.resolve("magic"))
    }

    @Test fun `resolve returns null for magic prefix with short token`() {
        assertNull(DeepLinkAllowlist.resolve("magic/tooshort"))
    }

    @Test fun `resolve returns null for magic prefix with slash in token`() {
        // Ensures path-traversal via magic/<token>/<extra> is rejected.
        // URL would be split at the slash; the resulting "token" is short and invalid.
        assertNull(DeepLinkAllowlist.resolve("magic/abc/extra"))
    }

    @Test fun `resolve returns null for magic prefix with disallowed chars`() {
        assertNull(DeepLinkAllowlist.resolve("magic/abc+badtoken123456789"))
    }

    // ── 4. Expired-token note ─────────────────────────────────────────────────
    //
    // The Android client performs shape-only validation; true expiry is enforced
    // server-side (15-minute one-time-use TTL). A token that looks valid but has
    // expired will still pass validateMagicToken locally. The server returns HTTP
    // 410 Gone; LoginViewModel maps that to "This sign-in link has expired".
    // This test documents the intended split of responsibilities.

    @Test fun `validateMagicToken accepts valid-shaped token regardless of age (server enforces TTL)`() {
        // An "old" token has the same shape as a fresh one — the client cannot
        // tell the difference. This is by design; the server is authoritative
        // on expiry.
        val validShapedToken = "expiredLookingButShapeIsOK12345"
        assertNotNull(DeepLinkAllowlist.validateMagicToken(validShapedToken))
    }

    // ── 5. Allowlist cross-checks — magic path does not bleed into other routes

    @Test fun `resolve does not accept magic prefix for setup routes`() {
        // Ensure "magic/..." is not confused with "setup/..." handling.
        val setupToken = "validSetupToken123456789"
        assertNull(DeepLinkAllowlist.resolve("magic/setup/$setupToken"))
    }

    @Test fun `resolve does not accept arbitrary host with magic prefix in path`() {
        // "ticket/magic/..." should NOT resolve as a magic-link route.
        assertNull(DeepLinkAllowlist.resolve("ticket/magic/$typicalToken"))
    }
}
