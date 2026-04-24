package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.net.URI

/**
 * §2.20 L449 — Unit tests for SSO callback URI parsing.
 *
 * Validates the query-parameter extraction logic that MainActivity uses to pull
 * `code` + `state` out of `bizarrecrm://sso/callback?code=…&state=…` URIs.
 *
 * These tests exercise the same parse path as MainActivity.resolveDeepLink:
 *   scheme == "bizarrecrm"
 *   host == "sso"
 *   path (trimmed) == "callback"
 *   query parameter "code"  — must be non-blank
 *   query parameter "state" — must be non-blank
 *
 * Uses java.net.URI so no Android runtime (Robolectric) is needed — pure JVM test.
 */
class SsoCallbackParserTest {

    // ── pure-JVM parser mirroring MainActivity.resolveDeepLink SSO branch ──

    private data class SsoCallbackResult(val code: String?, val state: String?)

    /**
     * Mirrors the SSO-callback branch in MainActivity.resolveDeepLink.
     * Uses java.net.URI for pure-JVM query parsing (no android.net.Uri needed).
     */
    private fun parseSsoCallbackUri(uriStr: String): SsoCallbackResult {
        return try {
            val uri = URI(uriStr)
            if (uri.scheme != "bizarrecrm") return SsoCallbackResult(null, null)
            if (uri.host != "sso") return SsoCallbackResult(null, null)
            if (uri.path?.trimStart('/') != "callback") return SsoCallbackResult(null, null)
            val params = parseQuery(uri.rawQuery)
            val code = params["code"]?.takeIf { it.isNotBlank() }
            val state = params["state"]?.takeIf { it.isNotBlank() }
            SsoCallbackResult(code, state)
        } catch (_: Exception) {
            SsoCallbackResult(null, null)
        }
    }

    /** Parses `key=value&key2=value2` query strings into a map. Decodes percent-encoding. */
    private fun parseQuery(rawQuery: String?): Map<String, String> {
        if (rawQuery.isNullOrBlank()) return emptyMap()
        return rawQuery.split("&").mapNotNull { pair ->
            val eq = pair.indexOf('=')
            if (eq < 0) null
            else {
                val key = java.net.URLDecoder.decode(pair.substring(0, eq), "UTF-8")
                val value = java.net.URLDecoder.decode(pair.substring(eq + 1), "UTF-8")
                key to value
            }
        }.toMap()
    }

    // ── valid callback ───────────────────────────────────────────────

    @Test fun `parses valid SSO callback with code and state`() {
        val result = parseSsoCallbackUri("bizarrecrm://sso/callback?code=auth_code_123&state=csrf_state_abc")
        assertEquals("auth_code_123", result.code)
        assertEquals("csrf_state_abc", result.state)
    }

    @Test fun `parses callback with additional query parameters`() {
        val result = parseSsoCallbackUri(
            "bizarrecrm://sso/callback?code=abc123&state=xyz789&session_state=ignored"
        )
        assertEquals("abc123", result.code)
        assertEquals("xyz789", result.state)
    }

    // ── state mismatch ───────────────────────────────────────────────

    @Test fun `state mismatch is detectable by comparing returned state`() {
        val result = parseSsoCallbackUri("bizarrecrm://sso/callback?code=abc&state=wrong_state")
        val expectedState = "correct_state"
        // Caller is responsible for comparing result.state != expectedState
        assertEquals("abc", result.code)
        assertEquals("wrong_state", result.state)
        assert(result.state != expectedState) { "State mismatch should be caught by caller" }
    }

    // ── missing parameters ───────────────────────────────────────────

    @Test fun `missing code returns null code`() {
        val result = parseSsoCallbackUri("bizarrecrm://sso/callback?state=csrf_state_abc")
        assertNull(result.code)
        assertEquals("csrf_state_abc", result.state)
    }

    @Test fun `missing state returns null state`() {
        val result = parseSsoCallbackUri("bizarrecrm://sso/callback?code=auth_code_123")
        assertEquals("auth_code_123", result.code)
        assertNull(result.state)
    }

    @Test fun `blank code returns null`() {
        val result = parseSsoCallbackUri("bizarrecrm://sso/callback?code=&state=csrf_abc")
        assertNull(result.code)
    }

    @Test fun `blank state returns null`() {
        val result = parseSsoCallbackUri("bizarrecrm://sso/callback?code=abc&state=")
        assertNull(result.state)
    }

    @Test fun `missing both code and state returns null pair`() {
        val result = parseSsoCallbackUri("bizarrecrm://sso/callback")
        assertNull(result.code)
        assertNull(result.state)
    }

    // ── wrong scheme / host / path ───────────────────────────────────

    @Test fun `wrong scheme is rejected`() {
        val result = parseSsoCallbackUri("https://sso/callback?code=abc&state=xyz")
        assertNull(result.code)
        assertNull(result.state)
    }

    @Test fun `wrong host is rejected`() {
        val result = parseSsoCallbackUri("bizarrecrm://ticket/callback?code=abc&state=xyz")
        assertNull(result.code)
        assertNull(result.state)
    }

    @Test fun `wrong path is rejected`() {
        val result = parseSsoCallbackUri("bizarrecrm://sso/other?code=abc&state=xyz")
        assertNull(result.code)
        assertNull(result.state)
    }

    @Test fun `bare sso host without path callback is rejected`() {
        // bizarrecrm://sso alone — no "/callback" segment
        val result = parseSsoCallbackUri("bizarrecrm://sso?code=abc&state=xyz")
        assertNull(result.code)
        assertNull(result.state)
    }
}
