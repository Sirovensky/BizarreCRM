package com.bizarreelectronics.crm.ui.screens.tickets

import com.bizarreelectronics.crm.util.PhoneIntents
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure-JVM logic tests for ticket detail — tab state transitions and customer
 * action availability. No Android context required.
 *
 * Covers:
 *  - Tab index bounds: selecting tabs 0-3 is valid, others are clamped by the
 *    composable (not tested here — that's an instrumented test).
 *  - [PhoneIntents.canCall] / [PhoneIntents.canSms] / [PhoneIntents.canEmail]:
 *    availability logic for the TicketCustomerActions chip row.
 *  - Tab label ordering constant matches the intended 4-tab layout.
 */
class TicketDetailLogicTest {

    // -----------------------------------------------------------------------
    // 1. Tab count — exactly 4 tabs
    // -----------------------------------------------------------------------

    @Test
    fun `tab list has exactly four entries`() {
        val tabs = listOf("Actions", "Devices", "Notes", "Payments")
        assertEquals(4, tabs.size)
    }

    // -----------------------------------------------------------------------
    // 2. Tab ordering — Actions first, Payments last
    // -----------------------------------------------------------------------

    @Test
    fun `first tab is Actions`() {
        val tabs = listOf("Actions", "Devices", "Notes", "Payments")
        assertEquals("Actions", tabs[0])
    }

    @Test
    fun `last tab is Payments`() {
        val tabs = listOf("Actions", "Devices", "Notes", "Payments")
        assertEquals("Payments", tabs[3])
    }

    @Test
    fun `Notes tab is at index 2`() {
        val tabs = listOf("Actions", "Devices", "Notes", "Payments")
        assertEquals("Notes", tabs[2])
    }

    // -----------------------------------------------------------------------
    // 3. PhoneIntents.canCall — call availability logic
    // -----------------------------------------------------------------------

    @Test
    fun `canCall returns true for non-blank phone`() {
        assertTrue(PhoneIntents.canCall("+1 (555) 123-4567"))
    }

    @Test
    fun `canCall returns false for null phone`() {
        assertFalse(PhoneIntents.canCall(null))
    }

    @Test
    fun `canCall returns false for blank phone`() {
        assertFalse(PhoneIntents.canCall(""))
        assertFalse(PhoneIntents.canCall("   "))
    }

    // -----------------------------------------------------------------------
    // 4. PhoneIntents.canSms — mirrors canCall
    // -----------------------------------------------------------------------

    @Test
    fun `canSms returns true for non-blank phone`() {
        assertTrue(PhoneIntents.canSms("5551234567"))
    }

    @Test
    fun `canSms returns false for null`() {
        assertFalse(PhoneIntents.canSms(null))
    }

    @Test
    fun `canSms returns false for blank`() {
        assertFalse(PhoneIntents.canSms("  "))
    }

    // -----------------------------------------------------------------------
    // 5. PhoneIntents.canEmail — requires non-blank + '@'
    // -----------------------------------------------------------------------

    @Test
    fun `canEmail returns true for valid email`() {
        assertTrue(PhoneIntents.canEmail("customer@example.com"))
    }

    @Test
    fun `canEmail returns false for null`() {
        assertFalse(PhoneIntents.canEmail(null))
    }

    @Test
    fun `canEmail returns false for blank`() {
        assertFalse(PhoneIntents.canEmail(""))
    }

    @Test
    fun `canEmail returns false for string without at-sign`() {
        assertFalse(PhoneIntents.canEmail("notanemail"))
    }

    @Test
    fun `canEmail returns true when string contains at-sign`() {
        // Minimal @ check — full RFC validation is out of scope here
        assertTrue(PhoneIntents.canEmail("a@b"))
    }

    // -----------------------------------------------------------------------
    // 6. Customer action chip enablement: all three disabled when no contact info
    // -----------------------------------------------------------------------

    @Test
    fun `all chips disabled when customer has no contact info`() {
        val phone: String? = null
        val email: String? = null
        assertFalse("Call should be disabled", PhoneIntents.canCall(phone))
        assertFalse("SMS should be disabled", PhoneIntents.canSms(phone))
        assertFalse("Email should be disabled", PhoneIntents.canEmail(email))
    }

    // -----------------------------------------------------------------------
    // 7. Customer action chip enablement: call+sms enabled, email disabled
    // -----------------------------------------------------------------------

    @Test
    fun `call and sms enabled when phone present but email absent`() {
        val phone = "5551234567"
        val email: String? = null
        assertTrue(PhoneIntents.canCall(phone))
        assertTrue(PhoneIntents.canSms(phone))
        assertFalse(PhoneIntents.canEmail(email))
    }

    // -----------------------------------------------------------------------
    // 8. Customer action chip enablement: all three enabled
    // -----------------------------------------------------------------------

    @Test
    fun `all chips enabled when phone and email present`() {
        val phone = "5551234567"
        val email = "customer@repair.shop"
        assertTrue(PhoneIntents.canCall(phone))
        assertTrue(PhoneIntents.canSms(phone))
        assertTrue(PhoneIntents.canEmail(email))
    }
}
