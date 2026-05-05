package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * §2.4 (L302-L303) — Unit tests for [OtpParser.extractOtpDigits].
 *
 * All tests drive the pure [OtpParser] helper directly. [OtpParser] has no
 * Android framework dependencies (no Handler, no Context, no ClipboardManager)
 * so these tests run in a plain JVM environment without Robolectric.
 *
 * §1.6 L239 — Tests for [SensitiveMarker.isSensitive] cover the three detection
 * paths used by [ClipboardUtil.clearSensitiveIfPresent]. [SensitiveMarker] is a
 * pure Kotlin object with no Android framework dependencies — all branches run in
 * a plain JVM environment without Robolectric.
 *
 * Detection cases:
 *   1. All inputs false/null — clip is not sensitive (no-op on background).
 *   2. User plain-text label (not our sentinel) — must not be flagged as sensitive.
 *   3. Our SENSITIVE_LABEL present — must be flagged and cleared on background.
 *   4. compat extra == true (even with plain label) — must be flagged.
 */
class ClipboardUtilTest {

    // -------------------------------------------------------------------------
    // Null / empty inputs
    // -------------------------------------------------------------------------

    @Test fun nullTextReturnsNull() {
        assertNull(OtpParser.extractOtpDigits(null))
    }

    @Test fun emptyStringReturnsNull() {
        assertNull(OtpParser.extractOtpDigits(""))
    }

    @Test fun whitespaceOnlyStringReturnsNull() {
        assertNull(OtpParser.extractOtpDigits("   \n\t  "))
    }

    @Test fun textWithNoDigitsReturnsNull() {
        assertNull(OtpParser.extractOtpDigits("hello world"))
    }

    // -------------------------------------------------------------------------
    // Digit runs too short (< 4) or too long (> 8)
    // -------------------------------------------------------------------------

    @Test fun digitRunShorterThanRangeLowerBoundReturnsNull() {
        // "123" is only 3 digits — below the default lower bound of 4
        assertNull(OtpParser.extractOtpDigits("Your OTP is 123"))
    }

    @Test fun digitRunLongerThanRangeUpperBoundReturnsNull() {
        // 10-digit phone number must not be mistaken for an OTP
        assertNull(OtpParser.extractOtpDigits("Call 1234567890 for help"))
    }

    // -------------------------------------------------------------------------
    // Exact-match cases
    // -------------------------------------------------------------------------

    @Test fun clean6DigitOtpIsDetected() {
        assertEquals("123456", OtpParser.extractOtpDigits("123456"))
    }

    @Test fun sixDigitOtpWithSurroundingWhitespaceAndNewlinesIsDetected() {
        assertEquals("987654", OtpParser.extractOtpDigits("  \n 987654 \t\n "))
    }

    @Test fun fourDigitOtpAtLowerBoundIsDetected() {
        assertEquals("4321", OtpParser.extractOtpDigits("4321"))
    }

    @Test fun eightDigitOtpAtUpperBoundIsDetected() {
        assertEquals("12345678", OtpParser.extractOtpDigits("12345678"))
    }

    @Test fun otpEmbeddedInSmsSentenceIsExtracted() {
        // Typical SMS from an authenticator service
        assertEquals("482910", OtpParser.extractOtpDigits("Your login code is 482910. Do not share it."))
    }

    @Test fun longestQualifyingRunWinsWhenMultipleRunsPresent() {
        // "12" (too short), "5678" (4 digits), "123456" (6 digits) — expect longest valid
        assertEquals("123456", OtpParser.extractOtpDigits("Code 12 or 5678 or 123456 use latest"))
    }

    // -------------------------------------------------------------------------
    // Custom range
    // -------------------------------------------------------------------------

    @Test fun customRange6to6RejectsFourDigitRun() {
        assertNull(OtpParser.extractOtpDigits("1234", 6..6))
    }

    @Test fun customRange6to6AcceptsSixDigitRun() {
        assertEquals("654321", OtpParser.extractOtpDigits("654321", 6..6))
    }

    @Test fun customRange4to4AcceptsExactlyFourDigits() {
        assertEquals("9876", OtpParser.extractOtpDigits("  9876  ", 4..4))
    }

    @Test fun customRange4to4RejectsSixDigitRun() {
        // 6 digits is outside 4..4
        assertNull(OtpParser.extractOtpDigits("123456", 4..4))
    }

    // -------------------------------------------------------------------------
    // §1.6 L239 — SensitiveMarker.isSensitive detection
    //             (pure Kotlin — no Android framework, no Robolectric needed)
    // -------------------------------------------------------------------------

    /**
     * When no marker is present the clip must not be flagged — ensures
     * [clearSensitiveIfPresent] is a no-op for empty / non-sensitive state.
     */
    @Test fun sensitiveMarker_noMarkers_returnsFalse() {
        assertFalse(SensitiveMarker.isSensitive(label = null, compatExtra = false, aospExtra = false))
    }

    /**
     * A user's own plain-text copy (arbitrary label, no extras) must NOT
     * be cleared — [isSensitive] must return false to protect user content.
     */
    @Test fun sensitiveMarker_userPlainLabel_returnsFalse() {
        assertFalse(SensitiveMarker.isSensitive(label = "Ticket #1234", compatExtra = false, aospExtra = false))
    }

    /**
     * A clip tagged with [ClipboardUtil.SENSITIVE_LABEL] by [copySensitive]
     * must be detected — this is the primary seal path on all API levels.
     */
    @Test fun sensitiveMarker_sensitiveLabelPresent_returnsTrue() {
        assertTrue(SensitiveMarker.isSensitive(label = ClipboardUtil.SENSITIVE_LABEL, compatExtra = false, aospExtra = false))
    }

    /**
     * A clip with [compatExtra] == true (set on API 24+ by [copySensitive])
     * must be detected even if the label was somehow overwritten.
     */
    @Test fun sensitiveMarker_compatExtraTrue_returnsTrue() {
        assertTrue(SensitiveMarker.isSensitive(label = "some-label", compatExtra = true, aospExtra = false))
    }
}
