package com.bizarreelectronics.crm.ui.screens.estimates

import com.bizarreelectronics.crm.data.local.db.entities.EstimateEntity
import com.bizarreelectronics.crm.ui.screens.estimates.components.EstimateFilterState
import com.bizarreelectronics.crm.ui.screens.estimates.components.isExpiringSoon
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for estimate list filtering and [isExpiringSoon] chip logic.
 *
 * All tests are pure JVM — no Android context required.
 *
 * Fixtures:
 *   A — Draft, Alice Smith,  created 2024-01-10, validUntil=2024-01-15 (past → expiring)
 *   B — Sent,  Bob Jones,   created 2024-03-01, validUntil=2026-12-31 (far future)
 *   C — Approved, Carol Lee, created 2024-06-20, validUntil=null
 *   D — Rejected, Dave Wu,   created 2024-02-14, validUntil=null
 *   E — Expired, Eve Kim,   created 2023-11-01, validUntil=2023-11-15 (past)
 */
class EstimateFilterTest {

    private val estimateA = stub(
        id = 1L, status = "draft", customerName = "Alice Smith",
        createdAt = "2024-01-10 08:00:00", validUntil = "2024-01-15",
    )
    private val estimateB = stub(
        id = 2L, status = "sent", customerName = "Bob Jones",
        createdAt = "2024-03-01 09:00:00", validUntil = "2026-12-31",
    )
    private val estimateC = stub(
        id = 3L, status = "approved", customerName = "Carol Lee",
        createdAt = "2024-06-20 10:00:00", validUntil = null,
    )
    private val estimateD = stub(
        id = 4L, status = "rejected", customerName = "Dave Wu",
        createdAt = "2024-02-14 11:00:00", validUntil = null,
    )
    private val estimateE = stub(
        id = 5L, status = "expired", customerName = "Eve Kim",
        createdAt = "2023-11-01 07:00:00", validUntil = "2023-11-15",
    )

    private val all = listOf(estimateA, estimateB, estimateC, estimateD, estimateE)

    // ── applyFilters helpers ──────────────────────────────────────────────────

    private fun applyFilters(
        estimates: List<EstimateEntity>,
        statusFilter: String = "All",
        filters: EstimateFilterState = EstimateFilterState(),
    ): List<EstimateEntity> {
        return estimates.filter { e ->
            val statusOk = statusFilter == "All" || e.status.equals(statusFilter, ignoreCase = true)
            val customerOk = filters.customerQuery.isBlank() ||
                e.customerName?.contains(filters.customerQuery, ignoreCase = true) == true
            val dateFromOk = filters.dateFrom.isBlank() || e.createdAt >= filters.dateFrom
            val dateToOk = filters.dateTo.isBlank() || e.createdAt.take(10) <= filters.dateTo
            statusOk && customerOk && dateFromOk && dateToOk
        }
    }

    // ── 1. Status filter: All ─────────────────────────────────────────────────

    @Test
    fun `All status returns every estimate`() {
        val result = applyFilters(all, statusFilter = "All")
        assertEquals(5, result.size)
    }

    // ── 2. Status filter: Draft ───────────────────────────────────────────────

    @Test
    fun `Draft status filter returns only draft estimates`() {
        val result = applyFilters(all, statusFilter = "Draft")
        assertEquals(listOf(1L), result.map { it.id })
    }

    // ── 3. Status filter: Approved ────────────────────────────────────────────

    @Test
    fun `Approved status filter returns only approved estimates`() {
        val result = applyFilters(all, statusFilter = "Approved")
        assertEquals(listOf(3L), result.map { it.id })
    }

    // ── 4. Status filter: Expired ─────────────────────────────────────────────

    @Test
    fun `Expired status filter returns only expired estimates`() {
        val result = applyFilters(all, statusFilter = "Expired")
        assertEquals(listOf(5L), result.map { it.id })
    }

    // ── 5. Customer name filter (case-insensitive) ───────────────────────────

    @Test
    fun `Customer query filters case-insensitively`() {
        val result = applyFilters(all, filters = EstimateFilterState(customerQuery = "bob"))
        assertEquals(listOf(2L), result.map { it.id })
    }

    // ── 6. Customer query partial match ──────────────────────────────────────

    @Test
    fun `Customer query partial match works`() {
        val result = applyFilters(all, filters = EstimateFilterState(customerQuery = "li"))
        // Alice Smith (ali) and Carol Lee (no match), Dave Wu (no), Eve Kim (no), Bob (no)
        assertEquals(listOf(1L), result.map { it.id })
    }

    // ── 7. Date-from filter ───────────────────────────────────────────────────

    @Test
    fun `dateFrom excludes estimates created before cutoff`() {
        val result = applyFilters(all, filters = EstimateFilterState(dateFrom = "2024-03-01"))
        // B(2024-03-01), C(2024-06-20) — A and D before, E before
        val ids = result.map { it.id }.sorted()
        assertEquals(listOf(2L, 3L), ids)
    }

    // ── 8. Date-to filter ─────────────────────────────────────────────────────

    @Test
    fun `dateTo excludes estimates created after cutoff`() {
        val result = applyFilters(all, filters = EstimateFilterState(dateTo = "2024-01-31"))
        // A(2024-01-10), E(2023-11-01) qualify
        val ids = result.map { it.id }.sorted()
        assertEquals(listOf(1L, 5L), ids)
    }

    // ── 9. Combined status + customer ────────────────────────────────────────

    @Test
    fun `Status and customer combined filter`() {
        val result = applyFilters(
            all,
            statusFilter = "Sent",
            filters = EstimateFilterState(customerQuery = "Jones"),
        )
        assertEquals(listOf(2L), result.map { it.id })
    }

    // ── 10. No matches ────────────────────────────────────────────────────────

    @Test
    fun `Filter with no matches returns empty list`() {
        val result = applyFilters(all, filters = EstimateFilterState(customerQuery = "Nonexistent Person"))
        assertTrue(result.isEmpty())
    }

    // ── 11. Empty input ───────────────────────────────────────────────────────

    @Test
    fun `Empty list returns empty list regardless of filters`() {
        val result = applyFilters(emptyList(), statusFilter = "Draft")
        assertTrue(result.isEmpty())
    }

    // ── 12. isExpiringSoon — past date always expiring ────────────────────────

    @Test
    fun `isExpiringSoon returns true for past validUntil date`() {
        assertTrue(isExpiringSoon("2020-01-01"))
    }

    // ── 13. isExpiringSoon — far future date not expiring ────────────────────

    @Test
    fun `isExpiringSoon returns false for date more than 7 days in future`() {
        // Pick a date guaranteed to be > 7 days from any foreseeable test run
        assertFalse(isExpiringSoon("2099-12-31"))
    }

    // ── 14. isExpiringSoon — null returns false ───────────────────────────────

    @Test
    fun `isExpiringSoon returns false for null validUntil`() {
        assertFalse(isExpiringSoon(null))
    }

    // ── 15. isExpiringSoon — blank string returns false ───────────────────────

    @Test
    fun `isExpiringSoon returns false for blank validUntil`() {
        assertFalse(isExpiringSoon(""))
    }

    // ── 16. EstimateFilterState.isActive ─────────────────────────────────────

    @Test
    fun `EstimateFilterState isActive false when all fields blank`() {
        assertFalse(EstimateFilterState().isActive)
    }

    @Test
    fun `EstimateFilterState isActive true when customerQuery set`() {
        assertTrue(EstimateFilterState(customerQuery = "Alice").isActive)
    }

    @Test
    fun `EstimateFilterState isActive true when dateFrom set`() {
        assertTrue(EstimateFilterState(dateFrom = "2024-01-01").isActive)
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    private fun stub(
        id: Long,
        status: String,
        customerName: String?,
        createdAt: String,
        validUntil: String?,
    ) = EstimateEntity(
        id = id,
        orderId = "EST-$id",
        customerId = null,
        customerName = customerName,
        status = status,
        discount = 0L,
        notes = null,
        validUntil = validUntil,
        subtotal = 10000L,
        totalTax = 0L,
        total = 10000L,
        convertedTicketId = null,
        createdAt = createdAt,
        updatedAt = createdAt,
    )
}
