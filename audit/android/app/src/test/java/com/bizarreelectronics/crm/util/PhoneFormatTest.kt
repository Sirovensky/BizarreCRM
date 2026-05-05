package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * §31.1 — unit coverage for the canonical phone-display helper. The
 * "+1 (XXX)-XXX-XXXX" format is referenced across tickets, customers,
 * invoices, and SMS, so drift here surfaces everywhere.
 */
class PhoneFormatTest {

    @Test fun `null or blank returns empty string`() {
        assertEquals("", formatPhoneDisplay(null))
        assertEquals("", formatPhoneDisplay(""))
        assertEquals("", formatPhoneDisplay("   "))
    }

    @Test fun `10 raw digits normalize to the +1 canonical form`() {
        assertEquals("+1 (555)-555-1234", formatPhoneDisplay("5555551234"))
    }

    @Test fun `11 digits starting with 1 drop the leading 1`() {
        assertEquals("+1 (555)-555-1234", formatPhoneDisplay("15555551234"))
    }

    @Test fun `partly-formatted inputs are re-canonicalized`() {
        assertEquals("+1 (555)-555-1234", formatPhoneDisplay("(555) 555-1234"))
        assertEquals("+1 (555)-555-1234", formatPhoneDisplay("555-555-1234"))
        assertEquals("+1 (555)-555-1234", formatPhoneDisplay("+1 (555)-555-1234"))
        assertEquals("+1 (555)-555-1234", formatPhoneDisplay("+1.555.555.1234"))
    }

    @Test fun `short stubs are returned untouched`() {
        // 9 digits is ambiguous; don't guess, don't re-format.
        assertEquals("555-1234", formatPhoneDisplay("555-1234"))
        assertEquals("123", formatPhoneDisplay("123"))
    }

    @Test fun `international-like numbers are left alone`() {
        // 12 digits, non-US country code — leave user input untouched.
        assertEquals("+44 20 7946 0958", formatPhoneDisplay("+44 20 7946 0958"))
        // 11 digits that do NOT start with 1 → not US, leave alone.
        assertEquals("44207946095", formatPhoneDisplay("44207946095"))
    }
}
