package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * §2.4 (L302-L303) — Unit tests for [ClipboardUtil.extractOtpDigits].
 *
 * All tests drive the pure helper directly (no Android ClipboardManager
 * required), so they run in a plain JVM test environment without Robolectric.
 */
class ClipboardUtilTest {

    // -------------------------------------------------------------------------
    // Null / empty inputs
    // -------------------------------------------------------------------------

    @Test fun nullTextReturnsNull() {
        assertNull(ClipboardUtil.extractOtpDigits(null))
    }

    @Test fun emptyStringReturnsNull() {
        assertNull(ClipboardUtil.extractOtpDigits(""))
    }

    @Test fun whitespaceOnlyStringReturnsNull() {
        assertNull(ClipboardUtil.extractOtpDigits("   \n\t  "))
    }

    @Test fun textWithNoDigitsReturnsNull() {
        assertNull(ClipboardUtil.extractOtpDigits("hello world"))
    }

    // -------------------------------------------------------------------------
    // Digit runs too short (< 4) or too long (> 8)
    // -------------------------------------------------------------------------

    @Test fun digitRunShorterThanRangeLowerBoundReturnsNull() {
        // "123" is only 3 digits — below the default lower bound of 4
        assertNull(ClipboardUtil.extractOtpDigits("Your OTP is 123"))
    }

    @Test fun digitRunLongerThanRangeUpperBoundReturnsNull() {
        // 10-digit phone number must not be mistaken for an OTP
        assertNull(ClipboardUtil.extractOtpDigits("Call 1234567890 for help"))
    }

    // -------------------------------------------------------------------------
    // Exact-match cases
    // -------------------------------------------------------------------------

    @Test fun clean6DigitOtpIsDetected() {
        assertEquals("123456", ClipboardUtil.extractOtpDigits("123456"))
    }

    @Test fun sixDigitOtpWithSurroundingWhitespaceAndNewlinesIsDetected() {
        assertEquals("987654", ClipboardUtil.extractOtpDigits("  \n 987654 \t\n "))
    }

    @Test fun fourDigitOtpAtLowerBoundIsDetected() {
        assertEquals("4321", ClipboardUtil.extractOtpDigits("4321"))
    }

    @Test fun eightDigitOtpAtUpperBoundIsDetected() {
        assertEquals("12345678", ClipboardUtil.extractOtpDigits("12345678"))
    }

    @Test fun otpEmbeddedInSmsSentenceIsExtracted() {
        // Typical SMS from an authenticator service
        assertEquals("482910", ClipboardUtil.extractOtpDigits("Your login code is 482910. Do not share it."))
    }

    @Test fun longestQualifyingRunWinsWhenMultipleRunsPresent() {
        // "12" (too short), "5678" (4 digits), "123456" (6 digits) — expect longest valid
        assertEquals("123456", ClipboardUtil.extractOtpDigits("Code 12 or 5678 or 123456 use latest"))
    }

    // -------------------------------------------------------------------------
    // Custom range (avoid dots in test names — JVM method name restriction)
    // -------------------------------------------------------------------------

    @Test fun customRange6to6RejectsFourDigitRun() {
        assertNull(ClipboardUtil.extractOtpDigits("1234", 6..6))
    }

    @Test fun customRange6to6AcceptsSixDigitRun() {
        assertEquals("654321", ClipboardUtil.extractOtpDigits("654321", 6..6))
    }

    @Test fun customRange4to4AcceptsExactlyFourDigits() {
        assertEquals("9876", ClipboardUtil.extractOtpDigits("  9876  ", 4..4))
    }

    @Test fun customRange4to4RejectsSixDigitRun() {
        // 6 digits is outside 4..4
        assertNull(ClipboardUtil.extractOtpDigits("123456", 4..4))
    }
}
