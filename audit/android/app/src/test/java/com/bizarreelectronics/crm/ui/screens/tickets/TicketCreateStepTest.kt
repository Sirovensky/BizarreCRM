package com.bizarreelectronics.crm.ui.screens.tickets

import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
import com.bizarreelectronics.crm.data.remote.dto.DeviceModelItem
import com.bizarreelectronics.crm.ui.screens.tickets.create.StepValidator
import com.bizarreelectronics.crm.ui.screens.tickets.create.StepValidator.ValidationResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [StepValidator] and the [TicketCreateSubStep] enum.
 *
 * No Android framework required — pure JVM.
 *
 * ### Cases
 *  1.  CUSTOMER step is invalid with no customer and no walk-in flag
 *  2.  CUSTOMER step is valid when a customer is selected
 *  3.  CUSTOMER step is valid when isWalkIn = true
 *  4.  DEVICE step is invalid with no device selected and empty custom name
 *  5.  DEVICE step is valid when selectedDevice is set
 *  6.  DEVICE step is valid when customDeviceName is non-blank
 *  7.  SERVICES step is always valid (user may skip)
 *  8.  DIAGNOSTIC step is always valid
 *  9.  PRICING step is always valid
 * 10.  ASSIGNEE step is always valid
 * 11.  REVIEW step is invalid when cart is empty
 * 12.  REVIEW step is invalid when no customer and not walk-in
 * 13.  REVIEW step is valid when cart has items and customer is selected
 * 14.  REVIEW step is valid when cart has items and isWalkIn is true
 * 15.  TicketCreateSubStep entries cover 7 steps in correct order
 * 16.  TicketCreateSubStep indices match ordinal positions
 * 17.  isValid delegates to validate correctly
 */
class TicketCreateStepTest {

    // ── Helpers ────────────────────────────────────────────────────────

    private fun emptyState() = TicketCreateUiState()

    private fun customerState() = emptyState().copy(
        selectedCustomer = CustomerListItem(
            id = 1L,
            firstName = "Jane",
            lastName = "Doe",
            email = null,
            phone = "555-1234",
            mobile = null,
            organization = null,
            city = null,
            state = null,
            customerGroupName = null,
            createdAt = null,
            ticketCount = 0,
        )
    )

    private fun walkInState() = emptyState().copy(isWalkIn = true)

    private fun deviceState(custom: String = "", device: DeviceModelItem? = null) =
        emptyState().copy(
            customDeviceName = custom,
            selectedDevice = device,
        )

    private fun cartState(customer: CustomerListItem? = null, walkIn: Boolean = false) =
        emptyState().copy(
            selectedCustomer = customer,
            isWalkIn = walkIn,
            cartItems = listOf(
                RepairCartItem(
                    deviceName = "iPhone 15",
                    category = "phone",
                    serviceName = "Screen replacement",
                    laborPrice = 120.0,
                )
            )
        )

    private fun fakeDevice() = DeviceModelItem(
        id = 42L,
        name = "iPhone 15",
        category = "phone",
        manufacturerId = 1L,
        manufacturerName = "Apple",
    )

    // ── Test cases ─────────────────────────────────────────────────────

    @Test fun `CUSTOMER step invalid when no customer and no walk-in`() {
        val result = StepValidator.validate(TicketCreateSubStep.CUSTOMER, emptyState())
        assertTrue(result is ValidationResult.Invalid)
    }

    @Test fun `CUSTOMER step valid when customer selected`() {
        val result = StepValidator.validate(TicketCreateSubStep.CUSTOMER, customerState())
        assertEquals(ValidationResult.Valid, result)
    }

    @Test fun `CUSTOMER step valid when isWalkIn true`() {
        val result = StepValidator.validate(TicketCreateSubStep.CUSTOMER, walkInState())
        assertEquals(ValidationResult.Valid, result)
    }

    @Test fun `DEVICE step invalid when no device and no custom name`() {
        val result = StepValidator.validate(TicketCreateSubStep.DEVICE, deviceState())
        assertTrue(result is ValidationResult.Invalid)
    }

    @Test fun `DEVICE step valid when selectedDevice is set`() {
        val result = StepValidator.validate(TicketCreateSubStep.DEVICE, deviceState(device = fakeDevice()))
        assertEquals(ValidationResult.Valid, result)
    }

    @Test fun `DEVICE step valid when customDeviceName is non-blank`() {
        val result = StepValidator.validate(TicketCreateSubStep.DEVICE, deviceState(custom = "My custom device"))
        assertEquals(ValidationResult.Valid, result)
    }

    @Test fun `SERVICES step is always valid`() {
        val result = StepValidator.validate(TicketCreateSubStep.SERVICES, emptyState())
        assertEquals(ValidationResult.Valid, result)
    }

    @Test fun `DIAGNOSTIC step is always valid`() {
        val result = StepValidator.validate(TicketCreateSubStep.DIAGNOSTIC, emptyState())
        assertEquals(ValidationResult.Valid, result)
    }

    @Test fun `PRICING step is always valid`() {
        val result = StepValidator.validate(TicketCreateSubStep.PRICING, emptyState())
        assertEquals(ValidationResult.Valid, result)
    }

    @Test fun `ASSIGNEE step is always valid`() {
        val result = StepValidator.validate(TicketCreateSubStep.ASSIGNEE, emptyState())
        assertEquals(ValidationResult.Valid, result)
    }

    @Test fun `REVIEW step invalid when cart is empty`() {
        val result = StepValidator.validate(TicketCreateSubStep.REVIEW, customerState())
        assertTrue(result is ValidationResult.Invalid)
    }

    @Test fun `REVIEW step invalid when no customer and not walk-in`() {
        val stateWithCart = emptyState().copy(
            cartItems = listOf(RepairCartItem(deviceName = "X", category = "phone", serviceName = null))
        )
        val result = StepValidator.validate(TicketCreateSubStep.REVIEW, stateWithCart)
        assertTrue(result is ValidationResult.Invalid)
    }

    @Test fun `REVIEW step valid when cart has items and customer selected`() {
        val result = StepValidator.validate(
            TicketCreateSubStep.REVIEW,
            cartState(customer = customerState().selectedCustomer),
        )
        assertEquals(ValidationResult.Valid, result)
    }

    @Test fun `REVIEW step valid when cart has items and isWalkIn true`() {
        val result = StepValidator.validate(TicketCreateSubStep.REVIEW, cartState(walkIn = true))
        assertEquals(ValidationResult.Valid, result)
    }

    @Test fun `TicketCreateSubStep has 7 entries in correct order`() {
        val entries = TicketCreateSubStep.entries
        assertEquals(7, entries.size)
        assertEquals(TicketCreateSubStep.CUSTOMER, entries[0])
        assertEquals(TicketCreateSubStep.DEVICE, entries[1])
        assertEquals(TicketCreateSubStep.SERVICES, entries[2])
        assertEquals(TicketCreateSubStep.DIAGNOSTIC, entries[3])
        assertEquals(TicketCreateSubStep.PRICING, entries[4])
        assertEquals(TicketCreateSubStep.ASSIGNEE, entries[5])
        assertEquals(TicketCreateSubStep.REVIEW, entries[6])
    }

    @Test fun `TicketCreateSubStep indices match ordinal`() {
        TicketCreateSubStep.entries.forEachIndexed { ordinal, step ->
            assertEquals("${step.name} index mismatch", ordinal, step.index)
        }
    }

    @Test fun `isValid delegates to validate correctly`() {
        assertFalse(StepValidator.isValid(TicketCreateSubStep.CUSTOMER, emptyState()))
        assertTrue(StepValidator.isValid(TicketCreateSubStep.CUSTOMER, walkInState()))
    }
}
