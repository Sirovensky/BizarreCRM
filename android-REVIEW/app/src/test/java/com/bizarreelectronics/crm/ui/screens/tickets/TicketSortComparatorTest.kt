package com.bizarreelectronics.crm.ui.screens.tickets

import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketSort
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Unit tests for [applySortOrder] — verifies correct ordering for all [TicketSort] options.
 *
 * Uses 5 hand-rolled [TicketEntity] stubs. Each test asserts the expected order by checking
 * the sorted id sequence. No Android context required (pure JVM).
 */
class TicketSortComparatorTest {

    // -----------------------------------------------------------------------
    // Test fixtures — 5 tickets with varied fields
    // -----------------------------------------------------------------------

    private val ticketA = stub(
        id = 1L,
        orderId = "T-001",
        customerName = "Alice Smith",
        createdAt = "2024-01-01 08:00:00",
        updatedAt = "2024-01-01 08:00:00",
        statusName = "Open",
        statusIsClosed = false,
        dueOn = "2024-02-10",
    )

    private val ticketB = stub(
        id = 2L,
        orderId = "T-002",
        customerName = "Bob Jones",
        createdAt = "2024-03-15 10:00:00",
        updatedAt = "2024-03-15 10:00:00",
        statusName = "In Progress",
        statusIsClosed = false,
        dueOn = "2024-04-01",
    )

    private val ticketC = stub(
        id = 3L,
        orderId = "T-003",
        customerName = "Carol White",
        createdAt = "2023-11-20 09:30:00",
        updatedAt = "2023-11-20 09:30:00",
        statusName = "Waiting for Parts",
        statusIsClosed = false,
        dueOn = null, // no due date — should sort last for DueDate sort
    )

    private val ticketD = stub(
        id = 4L,
        orderId = "T-004",
        customerName = "David Brown",
        createdAt = "2024-06-05 14:00:00",
        updatedAt = "2024-06-05 14:00:00",
        statusName = "Completed",
        statusIsClosed = true,
        dueOn = "2024-01-15",
    )

    private val ticketE = stub(
        id = 5L,
        orderId = "T-005",
        customerName = "Eve Davis",
        createdAt = "2024-02-28 11:00:00",
        updatedAt = "2024-02-28 11:00:00",
        statusName = "Cancelled",
        statusIsClosed = true,
        dueOn = "2024-03-01",
    )

    private val all = listOf(ticketA, ticketB, ticketC, ticketD, ticketE)

    // -----------------------------------------------------------------------
    // 1. Newest first — sorted by createdAt descending
    //    Expected: D(2024-06-05), B(2024-03-15), E(2024-02-28), A(2024-01-01), C(2023-11-20)
    // -----------------------------------------------------------------------

    @Test
    fun `Newest sort orders by createdAt descending`() {
        val sorted = applySortOrder(all, TicketSort.Newest)
        val ids = sorted.map { it.id }
        assertEquals(listOf(4L, 2L, 5L, 1L, 3L), ids)
    }

    // -----------------------------------------------------------------------
    // 2. Oldest first — sorted by createdAt ascending
    //    Expected: C(2023-11-20), A(2024-01-01), E(2024-02-28), B(2024-03-15), D(2024-06-05)
    // -----------------------------------------------------------------------

    @Test
    fun `Oldest sort orders by createdAt ascending`() {
        val sorted = applySortOrder(all, TicketSort.Oldest)
        val ids = sorted.map { it.id }
        assertEquals(listOf(3L, 1L, 5L, 2L, 4L), ids)
    }

    // -----------------------------------------------------------------------
    // 3. Status — sorted by statusName alphabetically (case-insensitive)
    //    statuses: Cancelled, Completed, In Progress, Open, Waiting for Parts
    //    ids:      E,         D,         B,            A,    C
    // -----------------------------------------------------------------------

    @Test
    fun `Status sort orders by statusName alphabetically`() {
        val sorted = applySortOrder(all, TicketSort.Status)
        val ids = sorted.map { it.id }
        assertEquals(listOf(5L, 4L, 2L, 1L, 3L), ids)
    }

    // -----------------------------------------------------------------------
    // 4. Urgency — sorted by TicketUrgency.ordinal ascending (Critical first)
    //    ticketUrgencyFor:
    //      A: Normal (open)
    //      B: Medium (in progress / repair)
    //      C: High   (waiting for parts)
    //      D: Low    (closed)
    //      E: Low    (closed)
    //    Expected order: C(High=1), B(Medium=2), A(Normal=3), D/E(Low=4) — D and E same level
    // -----------------------------------------------------------------------

    @Test
    fun `Urgency sort orders Critical then High then Medium then Normal then Low`() {
        val sorted = applySortOrder(all, TicketSort.Urgency)
        val ids = sorted.map { it.id }
        // C first (High), then B (Medium), then A (Normal), then D/E (Low — stable order)
        assertEquals(3L, ids[0])  // C — High
        assertEquals(2L, ids[1])  // B — Medium
        assertEquals(1L, ids[2])  // A — Normal
        // D and E are both Low; just verify they're at the end
        assert(ids[3] in listOf(4L, 5L)) { "ids[3] should be D or E" }
        assert(ids[4] in listOf(4L, 5L)) { "ids[4] should be D or E" }
    }

    // -----------------------------------------------------------------------
    // 5. Due date — nulls last, then ascending by dueOn string
    //    Due dates: A=2024-02-10, B=2024-04-01, C=null, D=2024-01-15, E=2024-03-01
    //    Nulls last: D, A, E, B — then C at the end
    //    Expected: D(2024-01-15), A(2024-02-10), E(2024-03-01), B(2024-04-01), C(null)
    // -----------------------------------------------------------------------

    @Test
    fun `DueDate sort orders nulls last then ascending by date string`() {
        val sorted = applySortOrder(all, TicketSort.DueDate)
        val ids = sorted.map { it.id }
        assertEquals(listOf(4L, 1L, 5L, 2L, 3L), ids)
    }

    // -----------------------------------------------------------------------
    // 6. Customer A–Z — sorted by customerName alphabetically (case-insensitive)
    //    Alice Smith, Bob Jones, Carol White, David Brown, Eve Davis
    //    A, B, C, D, E → ids: 1, 2, 3, 4, 5
    // -----------------------------------------------------------------------

    @Test
    fun `CustomerAZ sort orders by customerName alphabetically`() {
        val sorted = applySortOrder(all, TicketSort.CustomerAZ)
        val ids = sorted.map { it.id }
        assertEquals(listOf(1L, 2L, 3L, 4L, 5L), ids)
    }

    // -----------------------------------------------------------------------
    // 7. Empty list — all sorts return empty list without crash
    // -----------------------------------------------------------------------

    @Test
    fun `All sort orders handle empty list`() {
        for (sort in TicketSort.entries) {
            val sorted = applySortOrder(emptyList(), sort)
            assertEquals("$sort should return empty list", emptyList<TicketEntity>(), sorted)
        }
    }

    // -----------------------------------------------------------------------
    // 8. Single item — all sorts return single-element list
    // -----------------------------------------------------------------------

    @Test
    fun `All sort orders handle single-element list`() {
        for (sort in TicketSort.entries) {
            val sorted = applySortOrder(listOf(ticketA), sort)
            assertEquals("$sort should return [ticketA]", listOf(ticketA), sorted)
        }
    }

    // -----------------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------------

    private fun stub(
        id: Long,
        orderId: String,
        customerName: String,
        createdAt: String,
        updatedAt: String,
        statusName: String,
        statusIsClosed: Boolean,
        dueOn: String?,
    ) = TicketEntity(
        id = id,
        orderId = orderId,
        customerName = customerName,
        createdAt = createdAt,
        updatedAt = updatedAt,
        statusName = statusName,
        statusIsClosed = statusIsClosed,
        dueOn = dueOn,
    )
}
