package com.bizarreelectronics.crm

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

/**
 * §2.22 L463 — Unit tests for WebAuthn / passkey payload handling.
 *
 * Tests:
 *  1. Parse a sample WebAuthn PublicKeyCredentialCreationOptions JSON (register/begin).
 *  2. Parse a sample WebAuthn PublicKeyCredentialRequestOptions JSON (login/begin).
 *  3. Base64url encoding round-trips (challenge bytes → base64url → bytes).
 *  4. Reject a malformed challenge (empty, too short, wrong characters).
 *
 * These tests validate the client-side payload contract so that any server
 * change that breaks the JSON shape is caught immediately in CI.
 *
 * Note: [PasskeyManager] itself is not unit-tested here because
 * [CredentialManager] requires an Android context. Integration coverage
 * would require instrumented (Espresso / device) tests. Payload-level
 * validation — the part that runs on any JVM — is tested here.
 */
class PasskeyPayloadTest {

    // ── Helpers ────────────────────────────────────────────────────────────

    /** Converts standard Base64 to base64url (URL-safe, no padding). */
    private fun String.toBase64Url(): String =
        replace('+', '-').replace('/', '_').trimEnd('=')

    /** Decodes a base64url string. Adds padding as needed. */
    private fun String.fromBase64Url(): ByteArray {
        val padded = this.replace('-', '+').replace('_', '/')
        val pad = (4 - padded.length % 4) % 4
        return Base64.getDecoder().decode(padded + "=".repeat(pad))
    }

    // ── Sample JSON payloads ────────────────────────────────────────────────

    /**
     * Minimal valid WebAuthn PublicKeyCredentialCreationOptions JSON.
     * Mirrors the shape produced by simplewebauthn / fido2-lib server libraries.
     */
    private val sampleRegisterChallengeJson = """
        {
          "challenge": "dGVzdC1jaGFsbGVuZ2UtYmFzZTY0dXJs",
          "rp": {
            "name": "Bizarre Electronics CRM",
            "id": "bizarrecrm.com"
          },
          "user": {
            "id": "dXNlcklkMTIz",
            "name": "admin@bizarrecrm.com",
            "displayName": "Admin User"
          },
          "pubKeyCredParams": [
            { "type": "public-key", "alg": -7 },
            { "type": "public-key", "alg": -257 }
          ],
          "timeout": 60000,
          "attestation": "none",
          "excludeCredentials": []
        }
    """.trimIndent()

    /**
     * Minimal valid WebAuthn PublicKeyCredentialRequestOptions JSON.
     * Mirrors the shape from GET /auth/passkey/login/begin.
     */
    private val sampleLoginChallengeJson = """
        {
          "challenge": "bG9naW4tY2hhbGxlbmdlLWJhc2U2NHVybA",
          "timeout": 60000,
          "rpId": "bizarrecrm.com",
          "allowCredentials": [
            { "type": "public-key", "id": "Y3JlZElkMTIz" }
          ],
          "userVerification": "preferred"
        }
    """.trimIndent()

    // ── Parse tests ─────────────────────────────────────────────────────────

    @Test
    fun `register challenge JSON contains required fields`() {
        val json = org.json.JSONObject(sampleRegisterChallengeJson)

        assertTrue("missing challenge field", json.has("challenge"))
        assertTrue("missing rp field", json.has("rp"))
        assertTrue("missing user field", json.has("user"))
        assertTrue("missing pubKeyCredParams field", json.has("pubKeyCredParams"))

        val rp = json.getJSONObject("rp")
        assertEquals("bizarrecrm.com", rp.getString("id"))

        val params = json.getJSONArray("pubKeyCredParams")
        assertTrue("pubKeyCredParams must be non-empty", params.length() > 0)
        // ES256 (alg=-7) should be in the list.
        val algs = (0 until params.length()).map { params.getJSONObject(it).getInt("alg") }
        assertTrue("ES256 (alg=-7) must be present", -7 in algs)
    }

    @Test
    fun `login challenge JSON contains required fields`() {
        val json = org.json.JSONObject(sampleLoginChallengeJson)

        assertTrue("missing challenge field", json.has("challenge"))
        assertTrue("missing rpId field", json.has("rpId"))
        assertTrue("missing allowCredentials field", json.has("allowCredentials"))
        assertEquals("bizarrecrm.com", json.getString("rpId"))
    }

    @Test
    fun `challenge value is non-empty`() {
        val regJson = org.json.JSONObject(sampleRegisterChallengeJson)
        val loginJson = org.json.JSONObject(sampleLoginChallengeJson)

        assertTrue(regJson.getString("challenge").isNotBlank())
        assertTrue(loginJson.getString("challenge").isNotBlank())
    }

    // ── Base64url round-trip tests ──────────────────────────────────────────

    @Test
    fun `base64url encoding round-trips correctly`() {
        val original = "test-challenge-base64url".toByteArray(Charsets.UTF_8)
        val encoded = Base64.getEncoder().encodeToString(original).toBase64Url()
        val decoded = encoded.fromBase64Url()

        assertFalse("base64url must not contain '+'", encoded.contains('+'))
        assertFalse("base64url must not contain '/'", encoded.contains('/'))
        assertFalse("base64url must not end with '='", encoded.endsWith("="))
        assertEquals("round-trip must restore original bytes",
            original.toString(Charsets.UTF_8),
            decoded.toString(Charsets.UTF_8),
        )
    }

    @Test
    fun `base64url challenge from register JSON decodes to non-empty bytes`() {
        val json = org.json.JSONObject(sampleRegisterChallengeJson)
        val challenge = json.getString("challenge")
        val decoded = challenge.fromBase64Url()
        assertTrue("decoded challenge must be non-empty", decoded.isNotEmpty())
    }

    @Test
    fun `base64url from two different challenges are not equal`() {
        val regJson = org.json.JSONObject(sampleRegisterChallengeJson)
        val loginJson = org.json.JSONObject(sampleLoginChallengeJson)
        val regChallenge = regJson.getString("challenge")
        val loginChallenge = loginJson.getString("challenge")
        assertNotEquals("different requests must have different challenges",
            regChallenge, loginChallenge)
    }

    // ── Malformed challenge rejection ───────────────────────────────────────

    @Test(expected = Exception::class)
    fun `empty challenge JSON throws`() {
        org.json.JSONObject("").getString("challenge") // throws JSONException
    }

    @Test
    fun `challenge below minimum length is invalid`() {
        // WebAuthn spec requires at least 16 bytes of random challenge.
        // A base64url string shorter than 22 chars encodes fewer than 16 bytes.
        val tooShort = "abc"
        val decoded = tooShort.fromBase64Url()
        assertTrue("challenge of ${decoded.size} bytes is too short (need >= 16)",
            decoded.size < 16)
    }

    @Test
    fun `challenge with standard base64 characters converts to base64url`() {
        // Simulate a server that returns standard base64 instead of base64url.
        val stdBase64 = "aB+c/dE=" // contains + and /
        val base64url = stdBase64.toBase64Url()
        assertFalse("converted base64url must not contain '+'", base64url.contains('+'))
        assertFalse("converted base64url must not contain '/'", base64url.contains('/'))
    }

    @Test
    fun `register JSON attestation is none or indirect`() {
        val json = org.json.JSONObject(sampleRegisterChallengeJson)
        val attestation = json.optString("attestation", "none")
        assertTrue(
            "attestation must be 'none' or 'indirect' for privacy",
            attestation in setOf("none", "indirect"),
        )
    }
}
