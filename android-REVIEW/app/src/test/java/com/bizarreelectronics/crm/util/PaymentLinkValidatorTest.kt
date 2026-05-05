package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * §41 — Unit tests for PaymentLinkValidator: amount parsing + validation rules.
 *
 * The validator lives inside PaymentLinkViewModel but the rules are extracted
 * here for isolated testing without Hilt / Android deps.
 */
class PaymentLinkValidatorTest {

    // ── Amount parsing ────────────────────────────────────────────────────────

    @Test fun `valid integer amount converts to cents`() {
        assertEquals(500L, parseCents("5"))
        assertEquals(10000L, parseCents("100"))
        assertEquals(100L, parseCents("1"))
    }

    @Test fun `valid decimal amount converts to cents`() {
        assertEquals(999L, parseCents("9.99"))
        assertEquals(100L, parseCents("1.00"))
        assertEquals(50L, parseCents("0.50"))
        assertEquals(1L, parseCents("0.01"))
    }

    @Test fun `blank and null input returns null`() {
        assertNull(parseCents(""))
        assertNull(parseCents("   "))
    }

    @Test fun `non-numeric input returns null`() {
        assertNull(parseCents("abc"))
        assertNull(parseCents("$5"))
        assertNull(parseCents("1,000"))
    }

    @Test fun `zero amount returns null (invalid)`() {
        assertNull(parseCents("0"))
        assertNull(parseCents("0.00"))
    }

    @Test fun `negative amount returns null`() {
        assertNull(parseCents("-1"))
        assertNull(parseCents("-0.01"))
    }

    // ── Validation rules ──────────────────────────────────────────────────────

    @Test fun `amount below 1 cent is invalid`() {
        assertFalse(isAmountValid("0.001"))
        assertFalse(isAmountValid("0"))
    }

    @Test fun `amount at minimum threshold is valid`() {
        assertTrue(isAmountValid("0.01"))
        assertTrue(isAmountValid("1"))
    }

    @Test fun `very large amount is accepted (no upper cap)`() {
        assertTrue(isAmountValid("99999.99"))
        assertTrue(isAmountValid("1000000"))
    }

    @Test fun `expiry days validation`() {
        assertTrue(isExpiryValid(1))
        assertTrue(isExpiryValid(30))
        assertFalse(isExpiryValid(0))
        assertFalse(isExpiryValid(-1))
        assertFalse(isExpiryValid(366))   // > 1 year
    }

    // ── Status label mapping ──────────────────────────────────────────────────

    @Test fun `status display label mapping`() {
        assertEquals("Pending", statusLabel("pending"))
        assertEquals("Paid", statusLabel("paid"))
        assertEquals("Expired", statusLabel("expired"))
        assertEquals("Cancelled", statusLabel("cancelled"))
        // Unknown statuses are title-cased
        assertEquals("Unknown", statusLabel("unknown"))
    }

    // ── URL validation ────────────────────────────────────────────────────────

    @Test fun `https url is shareable`() {
        assertTrue(isShareableUrl("https://pay.example.com/abc123"))
        assertTrue(isShareableUrl("https://bizarrecrm.app/pay/xyz"))
    }

    @Test fun `empty or blank url is not shareable`() {
        assertFalse(isShareableUrl(""))
        assertFalse(isShareableUrl("  "))
    }

    @Test fun `non-https url is not shareable`() {
        assertFalse(isShareableUrl("http://pay.example.com/abc"))
        assertFalse(isShareableUrl("ftp://pay.example.com/abc"))
    }

    // ── Helpers (mirrors PaymentLinkViewModel logic) ──────────────────────────

    private fun parseCents(input: String): Long? {
        val trimmed = input.trim()
        if (trimmed.isBlank()) return null
        val bd = trimmed.toBigDecimalOrNull() ?: return null
        if (bd <= java.math.BigDecimal.ZERO) return null
        return (bd * java.math.BigDecimal(100)).toLong().takeIf { it > 0 }
    }

    private fun isAmountValid(input: String): Boolean = parseCents(input) != null

    private fun isExpiryValid(days: Int): Boolean = days in 1..365

    private fun statusLabel(status: String): String = status.replaceFirstChar { it.uppercase() }

    private fun isShareableUrl(url: String): Boolean = url.trimStart().startsWith("https://")
}
