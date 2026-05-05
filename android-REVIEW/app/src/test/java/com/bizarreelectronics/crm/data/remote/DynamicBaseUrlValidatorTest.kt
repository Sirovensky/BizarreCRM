package com.bizarreelectronics.crm.data.remote

import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * §31.7 — Static analysis: validates the URL injection-guard logic inside
 * [DynamicBaseUrlInterceptor.validate] and [DynamicBaseUrlInterceptor.isHostAllowed].
 *
 * These tests are pure JVM (no Android context, no Retrofit, no OkHttp network).
 * They assert the security-critical URL validation contract that protects against:
 *  - SSRF via user-supplied server URLs
 *  - Scheme injection (javascript:, file:, data:)
 *  - Userinfo injection (user:pass@host)
 *  - Whitespace / CR / LF injection
 *  - HTTP downgrade in release builds (HTTPS enforced)
 *
 * The companion `validate()` and `isHostAllowed()` methods are `internal` in the
 * `RetrofitClient.kt` file-level scope.  Since this test lives in the same package
 * (`com.bizarreelectronics.crm.data.remote`) it can access them directly.
 *
 * ActionPlan §31.7 — Static analysis: detekt + Android Lint + R8 obfuscation verify.
 */
class DynamicBaseUrlValidatorTest {

    // -------------------------------------------------------------------------
    // validate() — accepted inputs
    // -------------------------------------------------------------------------

    @Test
    fun `valid HTTPS URL is accepted`() {
        val result = DynamicBaseUrlInterceptor.validate("https://bizarrecrm.com/api/v1")
        assertNotNull("Valid HTTPS URL must be accepted", result)
    }

    @Test
    fun `HTTPS subdomain of production host is accepted`() {
        val result = DynamicBaseUrlInterceptor.validate("https://shop1.bizarrecrm.com")
        assertNotNull("HTTPS subdomain must be accepted", result)
    }

    @Test
    fun `HTTPS URL with explicit port 443 is accepted`() {
        val result = DynamicBaseUrlInterceptor.validate("https://bizarrecrm.com:443/api/v1/")
        assertNotNull("HTTPS with explicit port 443 must be accepted", result)
    }

    // -------------------------------------------------------------------------
    // validate() — rejected inputs (security hardening)
    // -------------------------------------------------------------------------

    @Test
    fun `URL with at-sign userinfo is rejected to prevent SSRF`() {
        val result = DynamicBaseUrlInterceptor.validate("https://user:pass@bizarrecrm.com")
        assertNull("URL with userinfo (@) must be rejected", result)
    }

    @Test
    fun `javascript-colon scheme injection is rejected`() {
        val result = DynamicBaseUrlInterceptor.validate("javascript:alert(1)")
        assertNull("javascript: scheme must be rejected", result)
    }

    @Test
    fun `data-colon scheme injection is rejected`() {
        val result = DynamicBaseUrlInterceptor.validate("data:text/html,<script>alert(1)</script>")
        assertNull("data: scheme must be rejected", result)
    }

    @Test
    fun `file scheme injection is rejected`() {
        val result = DynamicBaseUrlInterceptor.validate("file:///etc/passwd")
        assertNull("file: scheme must be rejected", result)
    }

    @Test
    fun `URL with embedded newline is rejected`() {
        val result = DynamicBaseUrlInterceptor.validate("https://bizarrecrm.com\nX-Custom: injected")
        assertNull("URL with newline must be rejected", result)
    }

    @Test
    fun `URL with embedded carriage-return is rejected`() {
        val result = DynamicBaseUrlInterceptor.validate("https://bizarrecrm.com\rX-Custom: injected")
        assertNull("URL with CR must be rejected", result)
    }

    @Test
    fun `URL with embedded tab is rejected`() {
        val result = DynamicBaseUrlInterceptor.validate("https://bizarrecrm.com\tpath")
        assertNull("URL with tab must be rejected", result)
    }

    @Test
    fun `URL with embedded space is rejected`() {
        val result = DynamicBaseUrlInterceptor.validate("https://bizarre crm.com")
        assertNull("URL with space must be rejected", result)
    }

    @Test
    fun `plain HTTP to external host is rejected`() {
        // HTTP is only permitted in DEBUG builds for LAN hosts.
        // In the JVM test environment, BuildConfig.DEBUG is typically false
        // (or the method enforces https regardless). At minimum, non-LAN HTTP must be rejected.
        val result = DynamicBaseUrlInterceptor.validate("http://evil.com/steal")
        // Either null (rejected entirely) or rejected because evil.com is not in the allow-list.
        // We accept both outcomes — the important assertion is that it does NOT produce a result
        // pointing to evil.com.
        if (result != null) {
            // If HTTP was somehow "accepted" (debug build), the host must still be a trusted host.
            val host = result.host.lowercase()
            val isLanHost = host == "localhost" || host == "127.0.0.1" ||
                host.startsWith("192.168.") || host.startsWith("10.") ||
                host.startsWith("172.")
            assert(isLanHost || host.endsWith("bizarrecrm.com") || host.endsWith("bizcrm.com")) {
                "HTTP URL to external host must not be allowed: $host"
            }
        }
    }

    @Test
    fun `empty string is rejected`() {
        val result = DynamicBaseUrlInterceptor.validate("")
        assertNull("Empty string must be rejected", result)
    }

    @Test
    fun `unparseable URL string is rejected`() {
        val result = DynamicBaseUrlInterceptor.validate("NOT A URL AT ALL")
        assertNull("Unparseable URL must be rejected", result)
    }

    // -------------------------------------------------------------------------
    // isHostAllowed() — accepted
    // -------------------------------------------------------------------------

    @Test
    fun `production host itself is allowed`() {
        // The exact value of PRODUCTION_HOST depends on BuildConfig.BASE_DOMAIN.
        // We test by constructing a URL and verifying validate() accepts it.
        val result = DynamicBaseUrlInterceptor.validate("https://bizarrecrm.com")
        assertNotNull("Production host must be allowed", result)
    }

    @Test
    fun `bizcrm com is allowed as an alias`() {
        val allowed = DynamicBaseUrlInterceptor.isHostAllowed("bizcrm.com")
        assert(allowed) { "bizcrm.com must be in the allow-list" }
    }

    @Test
    fun `subdomain of bizcrm com is allowed`() {
        val allowed = DynamicBaseUrlInterceptor.isHostAllowed("myshop.bizcrm.com")
        assert(allowed) { "Subdomain of bizcrm.com must be allowed" }
    }

    // -------------------------------------------------------------------------
    // isHostAllowed() — rejected
    // -------------------------------------------------------------------------

    @Test
    fun `arbitrary external host is not allowed`() {
        val allowed = DynamicBaseUrlInterceptor.isHostAllowed("evil.com")
        assert(!allowed) { "evil.com must NOT be in the allow-list" }
    }

    @Test
    fun `lookalike host with production name as path is not allowed`() {
        val allowed = DynamicBaseUrlInterceptor.isHostAllowed("bizarrecrm.com.evil.net")
        assert(!allowed) { "Lookalike domain with production name as subdomain of evil.net must be rejected" }
    }

    @Test
    fun `empty host is not allowed`() {
        val allowed = DynamicBaseUrlInterceptor.isHostAllowed("")
        assert(!allowed) { "Empty host must not be allowed" }
    }

    @Test
    fun `null host is not allowed`() {
        val allowed = DynamicBaseUrlInterceptor.isHostAllowed(null)
        assert(!allowed) { "Null host must not be allowed" }
    }
}
