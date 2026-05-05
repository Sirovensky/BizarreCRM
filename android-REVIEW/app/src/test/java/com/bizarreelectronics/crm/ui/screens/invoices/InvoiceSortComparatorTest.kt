package com.bizarreelectronics.crm.ui.screens.invoices

import com.bizarreelectronics.crm.data.local.db.entities.InvoiceEntity
import com.bizarreelectronics.crm.ui.screens.invoices.components.InvoiceSort
import com.bizarreelectronics.crm.ui.screens.invoices.components.applyInvoiceSortOrder
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Unit tests for [applyInvoiceSortOrder] — verifies correct ordering for all [InvoiceSort] options.
 *
 * Uses 5 hand-rolled [InvoiceEntity] stubs with varied dates, amounts, statuses.
 * No Android context required (pure JVM). All money values are in cents (Long).
 */
class InvoiceSortComparatorTest {

    // -----------------------------------------------------------------------
    // Fixtures — 5 invoices
    //   A: created 2024-01-01, total=$120.00, status=Unpaid, dueOn=2024-02-10
    //   B: created 2024-03-15, total=$45.00,  status=Paid,   dueOn=2024-04-01
    //   C: created 2023-11-20, total=$300.00, status=Partial, dueOn=null
    //   D: created 2024-06-05, total=$9.99,   status=Void,   dueOn=2024-01-15
    //   E: created 2024-02-28, total=$200.00, status=Unpaid, dueOn=2024-03-01
    // -----------------------------------------------------------------------

    private val invoiceA = stub(
        id = 1L,
        orderId = "INV-001",
        status = "Unpaid",
        totalCents = 12000L,   // $120.00
        amountDueCents = 12000L,
        createdAt = "2024-01-01 08:00:00",
        dueOn = "2024-02-10",
    )
    private val invoiceB = stub(
        id = 2L,
        orderId = "INV-002",
        status = "Paid",
        totalCents = 4500L,    // $45.00
        amountDueCents = 0L,
        createdAt = "2024-03-15 10:00:00",
        dueOn = "2024-04-01",
    )
    private val invoiceC = stub(
        id = 3L,
        orderId = "INV-003",
        status = "Partial",
        totalCents = 30000L,   // $300.00
        amountDueCents = 15000L,
        createdAt = "2023-11-20 09:30:00",
        dueOn = null,           // no due date — nulls-last for DueDate sort
    )
    private val invoiceD = stub(
        id = 4L,
        orderId = "INV-004",
        status = "Void",
        totalCents = 999L,     // $9.99
        amountDueCents = 0L,
        createdAt = "2024-06-05 14:00:00",
        dueOn = "2024-01-15",
    )
    private val invoiceE = stub(
        id = 5L,
        orderId = "INV-005",
        status = "Unpaid",
        totalCents = 20000L,   // $200.00
        amountDueCents = 20000L,
        createdAt = "2024-02-28 11:00:00",
        dueOn = "2024-03-01",
    )

    private val all = listOf(invoiceA, invoiceB, invoiceC, invoiceD, invoiceE)

    // -----------------------------------------------------------------------
    // 1. Newest first — by createdAt desc
    //    D(2024-06-05), B(2024-03-15), E(2024-02-28), A(2024-01-01), C(2023-11-20)
    // -----------------------------------------------------------------------

    @Test
    fun `Newest orders by createdAt descending`() {
        val ids = applyInvoiceSortOrder(all, InvoiceSort.Newest).map { it.id }
        assertEquals(listOf(4L, 2L, 5L, 1L, 3L), ids)
    }

    // -----------------------------------------------------------------------
    // 2. Oldest first — by createdAt asc
    //    C(2023-11-20), A(2024-01-01), E(2024-02-28), B(2024-03-15), D(2024-06-05)
    // -----------------------------------------------------------------------

    @Test
    fun `Oldest orders by createdAt ascending`() {
        val ids = applyInvoiceSortOrder(all, InvoiceSort.Oldest).map { it.id }
        assertEquals(listOf(3L, 1L, 5L, 2L, 4L), ids)
    }

    // -----------------------------------------------------------------------
    // 3. AmountHigh — by total cents desc
    //    C($300), E($200), A($120), B($45), D($9.99)  → ids: 3,5,1,2,4
    // -----------------------------------------------------------------------

    @Test
    fun `AmountHigh orders by total descending`() {
        val ids = applyInvoiceSortOrder(all, InvoiceSort.AmountHigh).map { it.id }
        assertEquals(listOf(3L, 5L, 1L, 2L, 4L), ids)
    }

    // -----------------------------------------------------------------------
    // 4. AmountLow — by total cents asc
    //    D($9.99), B($45), A($120), E($200), C($300)  → ids: 4,2,1,5,3
    // -----------------------------------------------------------------------

    @Test
    fun `AmountLow orders by total ascending`() {
        val ids = applyInvoiceSortOrder(all, InvoiceSort.AmountLow).map { it.id }
        assertEquals(listOf(4L, 2L, 1L, 5L, 3L), ids)
    }

    // -----------------------------------------------------------------------
    // 5. DueDate — nulls last, then asc
    //    D(2024-01-15), A(2024-02-10), E(2024-03-01), B(2024-04-01), C(null)
    //    → ids: 4,1,5,2,3
    // -----------------------------------------------------------------------

    @Test
    fun `DueDate orders nulls last then ascending`() {
        val ids = applyInvoiceSortOrder(all, InvoiceSort.DueDate).map { it.id }
        assertEquals(listOf(4L, 1L, 5L, 2L, 3L), ids)
    }

    // -----------------------------------------------------------------------
    // 6. Status — alphabetically (case-insensitive)
    //    Paid, Partial, Unpaid, Unpaid, Void
    //    B, C, A/E (both Unpaid — stable), D
    // -----------------------------------------------------------------------

    @Test
    fun `Status orders alphabetically case-insensitive`() {
        val sorted = applyInvoiceSortOrder(all, InvoiceSort.Status)
        val ids = sorted.map { it.id }
        assertEquals(2L, ids[0]) // Paid
        assertEquals(3L, ids[1]) // Partial
        // ids[2] and [3] are both "Unpaid" — stable original order A(1), E(5)
        assert(ids[2] in listOf(1L, 5L)) { "ids[2] should be A or E (both Unpaid)" }
        assert(ids[3] in listOf(1L, 5L)) { "ids[3] should be A or E (both Unpaid)" }
        assertEquals(4L, ids[4]) // Void
    }

    // -----------------------------------------------------------------------
    // 7. Empty list — all sorts return empty without crash
    // -----------------------------------------------------------------------

    @Test
    fun `All sorts handle empty list`() {
        for (sort in InvoiceSort.entries) {
            val result = applyInvoiceSortOrder(emptyList(), sort)
            assertEquals("$sort should return empty list", emptyList<InvoiceEntity>(), result)
        }
    }

    // -----------------------------------------------------------------------
    // 8. Single-element list — all sorts return it unchanged
    // -----------------------------------------------------------------------

    @Test
    fun `All sorts handle single-element list`() {
        for (sort in InvoiceSort.entries) {
            val result = applyInvoiceSortOrder(listOf(invoiceA), sort)
            assertEquals("$sort should return [invoiceA]", listOf(invoiceA), result)
        }
    }

    // -----------------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------------

    private fun stub(
        id: Long,
        orderId: String,
        status: String,
        totalCents: Long,
        amountDueCents: Long,
        createdAt: String,
        dueOn: String?,
    ) = InvoiceEntity(
        id = id,
        orderId = orderId,
        ticketId = null,
        customerId = null,
        status = status,
        total = totalCents,
        amountDue = amountDueCents,
        amountPaid = totalCents - amountDueCents,
        dueOn = dueOn,
        notes = null,
        createdBy = null,
        createdAt = createdAt,
        updatedAt = createdAt,
    )
}
