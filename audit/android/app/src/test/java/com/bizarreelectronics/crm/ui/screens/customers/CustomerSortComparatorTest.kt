package com.bizarreelectronics.crm.ui.screens.customers

import com.bizarreelectronics.crm.ui.screens.customers.components.CustomerSort
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Unit tests verifying [CustomerSort] enum contract (plan:L875).
 *
 * These tests confirm:
 * - Every [CustomerSort] entry has a non-blank [CustomerSort.label].
 * - Every [CustomerSort] entry has a non-blank [CustomerSort.sortKey].
 * - [CustomerSort.sortKey] values are all distinct (no accidental duplicate keys).
 * - The default sort ([CustomerSort.Recent]) maps to the expected sort key "recent".
 */
class CustomerSortComparatorTest {

    @Test
    fun `all sort options have non-blank labels`() {
        CustomerSort.entries.forEach { sort ->
            assert(sort.label.isNotBlank()) {
                "${sort.name} has a blank label"
            }
        }
    }

    @Test
    fun `all sort options have non-blank sort keys`() {
        CustomerSort.entries.forEach { sort ->
            assert(sort.sortKey.isNotBlank()) {
                "${sort.name} has a blank sortKey"
            }
        }
    }

    @Test
    fun `all sort keys are distinct`() {
        val keys = CustomerSort.entries.map { it.sortKey }
        val uniqueKeys = keys.toSet()
        assertEquals(
            "Duplicate sortKey found: ${keys.groupBy { it }.filter { it.value.size > 1 }.keys}",
            keys.size,
            uniqueKeys.size,
        )
    }

    @Test
    fun `default sort is Recent with key recent`() {
        assertEquals(CustomerSort.Recent, CustomerSort.entries.first())
        assertEquals("recent", CustomerSort.Recent.sortKey)
    }

    @Test
    fun `az sort key is az`() {
        assertEquals("az", CustomerSort.AZ.sortKey)
    }

    @Test
    fun `za sort key is za`() {
        assertEquals("za", CustomerSort.ZA.sortKey)
    }

    @Test
    fun `CustomerFilter filterKey is empty when no filter active`() {
        val filter = com.bizarreelectronics.crm.ui.screens.customers.components.CustomerFilter()
        val key = filter.filterKey
        assertEquals("", key)
    }

    @Test
    fun `CustomerFilter filterKey contains tier prefix when ltvTier set`() {
        val filter = com.bizarreelectronics.crm.ui.screens.customers.components.CustomerFilter(
            ltvTier = "VIP",
        )
        assert(filter.filterKey.contains("tier:VIP")) {
            "Expected filterKey to contain 'tier:VIP', got: '${filter.filterKey}'"
        }
    }

    @Test
    fun `CustomerFilter filterKey contains balance when hasBalance set`() {
        val filter = com.bizarreelectronics.crm.ui.screens.customers.components.CustomerFilter(
            hasBalance = true,
        )
        assert(filter.filterKey.contains("balance")) {
            "Expected filterKey to contain 'balance', got: '${filter.filterKey}'"
        }
    }

    @Test
    fun `CustomerFilter filterKey contains open_tickets when hasOpenTickets set`() {
        val filter = com.bizarreelectronics.crm.ui.screens.customers.components.CustomerFilter(
            hasOpenTickets = true,
        )
        assert(filter.filterKey.contains("open_tickets")) {
            "Expected filterKey to contain 'open_tickets', got: '${filter.filterKey}'"
        }
    }
}
