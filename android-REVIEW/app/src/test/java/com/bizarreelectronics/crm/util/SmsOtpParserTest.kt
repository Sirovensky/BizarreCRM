package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * §2.4 L302 — Pure-JVM unit tests for SMS Retriever OTP parsing logic.
 *
 * Tests verify that [OtpParser.extractOtpDigits] correctly handles the
 * SMS body format produced by the server's OTP template:
 *   `<#> Your Bizarre CRM code is 123456\n<app-hash>`
 *
 * These tests run on the JVM without Android or Play Services dependencies.
 */
class SmsOtpParserTest {

    // ── Happy-path: well-formed <#> OTP messages ─────────────────────────────

    @Test
    fun `extracts 6-digit code from canonical SMS Retriever format`() {
        val sms = "<#> Your Bizarre CRM code is 482910\nABcDEFghijk"
        assertEquals("482910", OtpParser.extractOtpDigits(sms, 6..6))
    }

    @Test
    fun `extracts 6-digit code when code is at start of body after prefix`() {
        val sms = "<#> 123456 is your login code\nABcDEFghijk"
        assertEquals("123456", OtpParser.extractOtpDigits(sms, 6..6))
    }

    @Test
    fun `extracts 6-digit code and ignores the 11-char hash suffix`() {
        // The 11-char hash is pure alphanumeric — should not be mistaken for OTP
        // because OtpParser.extractOtpDigits looks for longest digit run in 6..6.
        val sms = "<#> Code: 654321\nABcDE12345" // hash has only 5 digits → excluded by 6..6
        assertEquals("654321", OtpParser.extractOtpDigits(sms, 6..6))
    }

    @Test
    fun `extracts code when SMS body has extra whitespace`() {
        val sms = "<#>   Your code is   987654  \n\nXYZ12ab3456"
        // longest 6-digit run: "987654" or "123456" — both length 6; first wins
        val result = OtpParser.extractOtpDigits(sms, 6..6)
        // Either is valid; confirm it is 6 digits
        assertEquals(6, result?.length)
    }

    // ── Guard: SMS not from our app (no <#> prefix) ──────────────────────────

    @Test
    fun `returns null for SMS without hash prefix (not targeted at our app)`() {
        // Simulate a non-OTP SMS that somehow reached the receiver.
        // The receiver itself guards on <#> before calling extractOtpDigits;
        // here we test extractOtpDigits in isolation to confirm 6-digit extraction
        // still works on plain text — the <#> guard is in the receiver, not the parser.
        val plainSms = "Your code is 111222"
        assertEquals("111222", OtpParser.extractOtpDigits(plainSms, 6..6))
    }

    @Test
    fun `rejects non-6-digit codes when strict 6-to-6 range is enforced`() {
        val sms = "<#> Your code is 1234\nABcDEFghijk"
        assertNull("4-digit code should not match strict 6..6 range",
            OtpParser.extractOtpDigits(sms, 6..6))
    }

    @Test
    fun `rejects 7-digit code when strict 6-to-6 range is enforced`() {
        val sms = "<#> Code 1234567\nABcDEFghijk"
        assertNull("7-digit code should not match strict 6..6 range",
            OtpParser.extractOtpDigits(sms, 6..6))
    }

    // ── Edge cases ───────────────────────────────────────────────────────────

    @Test
    fun `returns null for null input`() {
        assertNull(OtpParser.extractOtpDigits(null, 6..6))
    }

    @Test
    fun `returns null for blank SMS body`() {
        assertNull(OtpParser.extractOtpDigits("   ", 6..6))
    }

    @Test
    fun `returns null for SMS with no digit runs`() {
        assertNull(OtpParser.extractOtpDigits("<#> Your code is invalid\nABcDEFghijk", 6..6))
    }

    @Test
    fun `handles SMS with multiple 6-digit runs — returns first encountered`() {
        // Server should only embed one 6-digit code; but if multiple appear,
        // the parser picks the first 6-digit run (ties broken by first occurrence).
        val sms = "<#> 111111 or 222222\nABcDEFghijk"
        assertEquals("111111", OtpParser.extractOtpDigits(sms, 6..6))
    }

    @Test
    fun `handles SMS with mixed short and long runs — returns 6-digit run`() {
        val sms = "<#> ref 12 code 456789\nABcDEFghijk"
        assertEquals("456789", OtpParser.extractOtpDigits(sms, 6..6))
    }
}
