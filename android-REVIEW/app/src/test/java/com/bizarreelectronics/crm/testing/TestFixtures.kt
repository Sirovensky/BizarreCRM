package com.bizarreelectronics.crm.testing

import com.bizarreelectronics.crm.data.local.db.entities.CustomerEntity
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
import com.bizarreelectronics.crm.data.remote.dto.TicketListItem

/**
 * Shared test fixture builders (ActionPlan §31.8).
 *
 * Provides minimal, mid-size, and edge-case tenant fixtures for unit tests
 * across the entire `src/test/` source set. Each builder function returns
 * sensible defaults that make tests readable without excessive boilerplate.
 *
 * Usage:
 * ```kotlin
 * val customer = TestFixtures.customer(id = 10L, firstName = "Alice")
 * val ticket   = TestFixtures.ticket(id = 1L, customerId = 10L)
 * ```
 *
 * NOTE: The full-size fixture DB pre-populated with 958 customers, 964 tickets,
 * and 487 inventory items (ActionPlan §31.8 second bullet) requires Room +
 * MigrationTestHelper running on an instrumented device. That fixture is
 * deferred to `src/androidTest/` once the instrumented test suite is set up.
 *
 * ## Tenant size presets
 *
 * | Preset          | Customers | Tickets | Inventory |
 * |-----------------|-----------|---------|-----------|
 * | [minimalTenant] | 1         | 1       | 0         |
 * | [midSizeTenant] | 20        | 50      | 10        |
 * | [edgeCaseTenant]| 1         | 0       | 0         | (customer with no tickets)
 */
object TestFixtures {

    // ── Timestamps ────────────────────────────────────────────────────────────

    const val TIMESTAMP_2026 = "2026-01-01 00:00:00"
    const val TIMESTAMP_2025 = "2025-06-15 12:00:00"

    // ── CustomerEntity builders ───────────────────────────────────────────────

    /**
     * Returns a [CustomerEntity] with the supplied overrides and sensible defaults.
     * All nullable fields default to null unless specified.
     */
    fun customerEntity(
        id: Long = 1L,
        firstName: String? = "Test",
        lastName: String? = "User",
        email: String? = "test@example.com",
        phone: String? = "555-0100",
        mobile: String? = null,
        organization: String? = null,
        city: String? = "Springfield",
        state: String? = "IL",
        createdAt: String = TIMESTAMP_2026,
        updatedAt: String = TIMESTAMP_2026,
        locallyModified: Boolean = false,
    ): CustomerEntity = CustomerEntity(
        id = id,
        firstName = firstName,
        lastName = lastName,
        email = email,
        phone = phone,
        mobile = mobile,
        organization = organization,
        city = city,
        state = state,
        createdAt = createdAt,
        updatedAt = updatedAt,
        locallyModified = locallyModified,
    )

    /** Returns a [CustomerEntity] representing an anonymous walk-in customer. */
    fun anonymousCustomerEntity(id: Long = 9999L): CustomerEntity = CustomerEntity(
        id = id,
        firstName = null,
        lastName = null,
        email = null,
        phone = null,
        createdAt = TIMESTAMP_2026,
        updatedAt = TIMESTAMP_2026,
    )

    /** Returns a [CustomerEntity] with the maximum practical field lengths. */
    fun largeCustomerEntity(id: Long = 2L): CustomerEntity = CustomerEntity(
        id = id,
        firstName = "A".repeat(50),
        lastName = "B".repeat(50),
        email = "${"x".repeat(40)}@${"y".repeat(40)}.com",
        phone = "1234567890",
        mobile = "0987654321",
        organization = "Org ".repeat(25).trimEnd(),
        city = "C".repeat(50),
        state = "ST",
        createdAt = TIMESTAMP_2026,
        updatedAt = TIMESTAMP_2026,
    )

    // ── TicketEntity builders ─────────────────────────────────────────────────

    /**
     * Returns a [TicketEntity] with sensible defaults.
     * All money fields default to 0 (no charge). Status defaults to "Open".
     */
    fun ticketEntity(
        id: Long = 1L,
        orderId: String = "T-$id",
        customerId: Long? = null,
        statusId: Long? = 1L,
        statusName: String? = "Open",
        statusColor: String? = "#4CAF50",
        statusIsClosed: Boolean = false,
        subtotal: Long = 0L,
        discount: Long = 0L,
        totalTax: Long = 0L,
        total: Long = 0L,
        createdAt: String = TIMESTAMP_2026,
        updatedAt: String = TIMESTAMP_2026,
        locallyModified: Boolean = false,
    ): TicketEntity = TicketEntity(
        id = id,
        orderId = orderId,
        customerId = customerId,
        statusId = statusId,
        statusName = statusName,
        statusColor = statusColor,
        statusIsClosed = statusIsClosed,
        subtotal = subtotal,
        discount = discount,
        totalTax = totalTax,
        total = total,
        createdAt = createdAt,
        updatedAt = updatedAt,
        locallyModified = locallyModified,
    )

    /** Returns a closed/completed ticket entity. */
    fun closedTicketEntity(id: Long = 100L, customerId: Long? = null): TicketEntity = ticketEntity(
        id = id,
        orderId = "T-CLOSED-$id",
        customerId = customerId,
        statusId = 99L,
        statusName = "Completed",
        statusColor = "#9E9E9E",
        statusIsClosed = true,
        total = 12500L,  // $125.00 in cents
    )

    /** Returns a ticket entity with a non-zero total (in cents). */
    fun paidTicketEntity(
        id: Long = 200L,
        totalCents: Long = 9999L,
        customerId: Long? = null,
    ): TicketEntity = ticketEntity(
        id = id,
        orderId = "T-PAID-$id",
        customerId = customerId,
        total = totalCents,
        subtotal = totalCents,
    )

    // ── DTO builders (ApiResponse shape) ─────────────────────────────────────

    /**
     * Returns a [TicketListItem] DTO as it arrives from the server.
     * Mirrors the shape used in [TicketRemoteMediatorTest].
     */
    fun ticketListItem(
        id: Long = 1L,
        orderId: String = "T-$id",
        customerId: Long? = null,
        statusName: String? = "Open",
        total: Double? = null,
        createdAt: String = TIMESTAMP_2026,
        updatedAt: String = TIMESTAMP_2026,
    ): TicketListItem = TicketListItem(
        id = id,
        orderId = orderId,
        customerId = customerId,
        customer = null,
        status = null,
        assignedUser = null,
        firstDevice = null,
        deviceCount = null,
        total = total,
        createdAt = createdAt,
        updatedAt = updatedAt,
        isPinned = null,
        latestInternalNote = null,
    )

    /**
     * Returns a [CustomerListItem] DTO as it arrives from the server.
     */
    fun customerListItem(
        id: Long = 1L,
        firstName: String? = "Test",
        lastName: String? = "User",
        email: String? = "test@example.com",
        phone: String? = "555-0100",
    ): CustomerListItem = CustomerListItem(
        id = id,
        firstName = firstName,
        lastName = lastName,
        email = email,
        phone = phone,
        mobile = null,
        organization = null,
        city = null,
        state = null,
        customerGroupName = null,
        createdAt = TIMESTAMP_2026,
        ticketCount = null,
    )

    /**
     * Wraps [payload] in a successful [ApiResponse].
     * Mirrors the server envelope `{ success: true, data: <payload> }`.
     */
    fun <T> successResponse(payload: T): ApiResponse<T> =
        ApiResponse(success = true, data = payload, message = null)

    /**
     * Returns a failed [ApiResponse] with [message] and null data.
     * Mirrors the server envelope `{ success: false, data: null, message: "..." }`.
     */
    fun <T> failureResponse(message: String = "Server error"): ApiResponse<T> =
        ApiResponse(success = false, data = null, message = message)

    // ── Tenant presets ────────────────────────────────────────────────────────

    /** Minimal tenant: one customer + one open ticket. */
    data class MinimalTenant(
        val customer: CustomerEntity,
        val ticket: TicketEntity,
    )

    fun minimalTenant(): MinimalTenant {
        val customer = customerEntity(id = 1L)
        val ticket = ticketEntity(id = 1L, customerId = 1L)
        return MinimalTenant(customer, ticket)
    }

    /** Mid-size tenant: 20 customers + 50 tickets (2-3 per customer) + 10 inventory items. */
    data class MidSizeTenant(
        val customers: List<CustomerEntity>,
        val tickets: List<TicketEntity>,
    )

    fun midSizeTenant(): MidSizeTenant {
        val customers = (1L..20L).map { i ->
            customerEntity(
                id = i,
                firstName = "Customer",
                lastName = "#$i",
                email = "cust$i@example.com",
                phone = "555-${i.toString().padStart(4, '0')}",
            )
        }
        val tickets = (1L..50L).map { i ->
            val customerId = ((i - 1) % 20L) + 1L  // round-robin across 20 customers
            ticketEntity(
                id = i,
                orderId = "T-${i.toString().padStart(4, '0')}",
                customerId = customerId,
                total = i * 1000L,  // ascending totals in cents
            )
        }
        return MidSizeTenant(customers, tickets)
    }

    /** Edge-case tenant: one customer with zero tickets. */
    data class EdgeCaseTenant(
        val customer: CustomerEntity,
        val tickets: List<TicketEntity>,
    )

    fun edgeCaseTenant(): EdgeCaseTenant {
        val customer = anonymousCustomerEntity(id = 1L)
        return EdgeCaseTenant(customer = customer, tickets = emptyList())
    }

    // ── Sequence helpers ──────────────────────────────────────────────────────

    /** Returns N customer entities with sequential IDs starting from [startId]. */
    fun customerSequence(count: Int, startId: Long = 1L): List<CustomerEntity> =
        (0 until count).map { i ->
            customerEntity(
                id = startId + i,
                firstName = "Customer",
                lastName = "${startId + i}",
                email = "cust${startId + i}@example.com",
            )
        }

    /** Returns N ticket entities with sequential IDs, all belonging to [customerId]. */
    fun ticketSequence(count: Int, customerId: Long = 1L, startId: Long = 1L): List<TicketEntity> =
        (0 until count).map { i ->
            ticketEntity(
                id = startId + i,
                orderId = "T-${startId + i}",
                customerId = customerId,
            )
        }
}
