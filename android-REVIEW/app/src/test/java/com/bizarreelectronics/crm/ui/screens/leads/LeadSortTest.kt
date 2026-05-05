package com.bizarreelectronics.crm.ui.screens.leads

import com.bizarreelectronics.crm.data.local.db.entities.LeadEntity
import com.bizarreelectronics.crm.ui.screens.leads.components.LeadSort
import com.bizarreelectronics.crm.ui.screens.leads.components.applySortOrder
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Unit tests for [applySortOrder] — verifies correct ordering for all [LeadSort] options.
 *
 * Uses 5 hand-rolled [LeadEntity] stubs with varied names, scores, and dates.
 * No Android context required (pure JVM).
 */
class LeadSortTest {

    // -----------------------------------------------------------------------
    // Test fixtures
    // -----------------------------------------------------------------------

    private val alice = stub(
        id = 1L, firstName = "Alice", lastName = "Smith",
        leadScore = 85, createdAt = "2024-01-01 08:00:00", updatedAt = "2024-06-01 12:00:00",
    )
    private val bob = stub(
        id = 2L, firstName = "Bob", lastName = "Jones",
        leadScore = 42, createdAt = "2024-03-15 10:00:00", updatedAt = "2024-03-16 09:00:00",
    )
    private val carol = stub(
        id = 3L, firstName = "Carol", lastName = "White",
        leadScore = 10, createdAt = "2023-11-20 09:30:00", updatedAt = "2023-11-21 08:00:00",
    )
    private val david = stub(
        id = 4L, firstName = "David", lastName = "Brown",
        leadScore = 97, createdAt = "2024-06-05 14:00:00", updatedAt = "2024-06-06 11:00:00",
    )
    private val eve = stub(
        id = 5L, firstName = "Eve", lastName = "Davis",
        leadScore = 63, createdAt = "2024-02-28 11:00:00", updatedAt = "2024-02-28 11:30:00",
    )

    private val all = listOf(alice, bob, carol, david, eve)

    // -----------------------------------------------------------------------
    // 1. NameAZ — alphabetical by first+last name
    //    Alice Smith(1), Bob Jones(2), Carol White(3), David Brown(4), Eve Davis(5)
    // -----------------------------------------------------------------------

    @Test
    fun `NameAZ sorts alphabetically by full name`() {
        val sorted = applySortOrder(all, LeadSort.NameAZ)
        assertEquals(listOf(1L, 2L, 3L, 4L, 5L), sorted.map { it.id })
    }

    // -----------------------------------------------------------------------
    // 2. CreatedNewest — descending by createdAt
    //    D(2024-06-05), B(2024-03-15), E(2024-02-28), A(2024-01-01), C(2023-11-20)
    // -----------------------------------------------------------------------

    @Test
    fun `CreatedNewest sorts by createdAt descending`() {
        val sorted = applySortOrder(all, LeadSort.CreatedNewest)
        assertEquals(listOf(4L, 2L, 5L, 1L, 3L), sorted.map { it.id })
    }

    // -----------------------------------------------------------------------
    // 3. CreatedOldest — ascending by createdAt
    //    C(2023-11-20), A(2024-01-01), E(2024-02-28), B(2024-03-15), D(2024-06-05)
    // -----------------------------------------------------------------------

    @Test
    fun `CreatedOldest sorts by createdAt ascending`() {
        val sorted = applySortOrder(all, LeadSort.CreatedOldest)
        assertEquals(listOf(3L, 1L, 5L, 2L, 4L), sorted.map { it.id })
    }

    // -----------------------------------------------------------------------
    // 4. LeadScore — descending: D(97), A(85), E(63), B(42), C(10)
    // -----------------------------------------------------------------------

    @Test
    fun `LeadScore sorts by score descending`() {
        val sorted = applySortOrder(all, LeadSort.LeadScore)
        assertEquals(listOf(4L, 1L, 5L, 2L, 3L), sorted.map { it.id })
    }

    // -----------------------------------------------------------------------
    // 5. LastActivity — descending by updatedAt
    //    A(2024-06-01), D(2024-06-06) — wait: D updated 2024-06-06, A updated 2024-06-01
    //    D(2024-06-06), A(2024-06-01), B(2024-03-16), E(2024-02-28), C(2023-11-21)
    // -----------------------------------------------------------------------

    @Test
    fun `LastActivity sorts by updatedAt descending`() {
        val sorted = applySortOrder(all, LeadSort.LastActivity)
        assertEquals(listOf(4L, 1L, 2L, 5L, 3L), sorted.map { it.id })
    }

    // -----------------------------------------------------------------------
    // 6. NextAction — ascending by updatedAt (proxy)
    //    C(2023-11-21), E(2024-02-28), B(2024-03-16), A(2024-06-01), D(2024-06-06)
    // -----------------------------------------------------------------------

    @Test
    fun `NextAction sorts by updatedAt ascending`() {
        val sorted = applySortOrder(all, LeadSort.NextAction)
        assertEquals(listOf(3L, 5L, 2L, 1L, 4L), sorted.map { it.id })
    }

    // -----------------------------------------------------------------------
    // 7. Empty list — all sorts return empty without crash
    // -----------------------------------------------------------------------

    @Test
    fun `All sorts handle empty list`() {
        for (sort in LeadSort.entries) {
            val result = applySortOrder(emptyList(), sort)
            assertEquals("$sort should return empty", emptyList<LeadEntity>(), result)
        }
    }

    // -----------------------------------------------------------------------
    // 8. Single-element list — all sorts return the same element
    // -----------------------------------------------------------------------

    @Test
    fun `All sorts handle single-element list`() {
        for (sort in LeadSort.entries) {
            val result = applySortOrder(listOf(alice), sort)
            assertEquals("$sort should return [alice]", listOf(alice), result)
        }
    }

    // -----------------------------------------------------------------------
    // 9. Immutability — original list is not mutated
    // -----------------------------------------------------------------------

    @Test
    fun `applySortOrder does not mutate original list`() {
        val original = listOf(david, carol, alice, eve, bob)
        val originalIds = original.map { it.id }.toList()
        applySortOrder(original, LeadSort.NameAZ)
        assertEquals("Original list must not be mutated", originalIds, original.map { it.id })
    }

    // -----------------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------------

    private fun stub(
        id: Long,
        firstName: String,
        lastName: String,
        leadScore: Int,
        createdAt: String,
        updatedAt: String,
    ) = LeadEntity(
        id = id,
        firstName = firstName,
        lastName = lastName,
        leadScore = leadScore,
        createdAt = createdAt,
        updatedAt = updatedAt,
    )
}
