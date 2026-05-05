package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * §31.1 — unit coverage for PhoneFormatter + CurrencyFormatter.
 *
 * [PhoneFormatter] predates the canonical [formatPhoneDisplay] +1 form —
 * these tests lock the "(XXX) XXX-XXXX" output that legacy callers still
 * depend on, and [PhoneFormatter.normalize] which is used by contact-match
 * lookups to strip formatting before DB queries.
 *
 * [CurrencyFormatter] is a thin wrapper over NumberFormat.getCurrencyInstance
 * with a locale-insensitive short variant. We pin the US locale format so a
 * locale change on the test machine doesn't silently break assertions.
 */
class FormattersTest {

    // --- PhoneFormatter.format ----------------------------------------------

    @Test fun `format returns empty for null or blank`() {
        assertEquals("", PhoneFormatter.format(null))
        assertEquals("", PhoneFormatter.format(""))
        assertEquals("", PhoneFormatter.format("  "))
    }

    @Test fun `format returns paren-dashed shape for 10 digits`() {
        assertEquals("(555) 555-1234", PhoneFormatter.format("5555551234"))
    }

    @Test fun `format strips leading 1 on 11 digits`() {
        assertEquals("(555) 555-1234", PhoneFormatter.format("15555551234"))
    }

    @Test fun `format leaves non-US or partial numbers untouched`() {
        assertEquals("555-1234", PhoneFormatter.format("555-1234"))
        assertEquals("+44 20 7946 0958", PhoneFormatter.format("+44 20 7946 0958"))
    }

    // --- PhoneFormatter.normalize -------------------------------------------

    @Test fun `normalize strips punctuation`() {
        assertEquals("5555551234", PhoneFormatter.normalize("(555) 555-1234"))
        assertEquals("5555551234", PhoneFormatter.normalize("+1 (555) 555-1234"))
    }

    @Test fun `normalize drops leading 1 from 11 digits`() {
        assertEquals("5555551234", PhoneFormatter.normalize("15555551234"))
    }

    @Test fun `normalize returns empty for null or blank`() {
        assertEquals("", PhoneFormatter.normalize(null))
        assertEquals("", PhoneFormatter.normalize(""))
    }

    // --- CurrencyFormatter --------------------------------------------------

    @Test fun `format produces locale currency string`() {
        // NumberFormat.getCurrencyInstance(Locale.US) → "$12.34" / "$0.00"
        assertEquals("$12.34", CurrencyFormatter.format(12.34))
        assertEquals("$0.00", CurrencyFormatter.format(0.0))
    }

    @Test fun `format rounds to two decimals`() {
        // NumberFormat's default rounding is HALF_EVEN. The halfway points
        // here are "0.345" / "0.355" which do NOT round-trip through IEEE-754
        // as exact halves (0.345 = 0.34500000000000003 in binary), so the
        // rounding lands on the nearer representable value — which for this
        // JVM is .35 / .36 respectively. Lock in the observed output so any
        // runtime rounding-mode change surfaces here.
        assertEquals("$12.35", CurrencyFormatter.format(12.345))
        assertEquals("$12.36", CurrencyFormatter.format(12.355))
    }

    @Test fun `formatShort drops thousands separator`() {
        // formatShort is a hand-rolled "$%.2f" — no grouping, used when every
        // character is precious (POS keypad preview).
        assertEquals("$1000.00", CurrencyFormatter.formatShort(1000.0))
        assertEquals("$12.34", CurrencyFormatter.formatShort(12.34))
    }
}
