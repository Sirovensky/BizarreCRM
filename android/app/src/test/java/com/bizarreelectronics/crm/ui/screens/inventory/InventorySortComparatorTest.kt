package com.bizarreelectronics.crm.ui.screens.inventory

import com.bizarreelectronics.crm.data.local.db.entities.InventoryItemEntity
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventorySort
import com.bizarreelectronics.crm.ui.screens.inventory.components.applyInventorySortOrder
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Unit tests for [applyInventorySortOrder] — verifies correct ordering for all [InventorySort]
 * options against 5 hand-rolled [InventoryItemEntity] stubs. No Android context required (pure JVM).
 */
class InventorySortComparatorTest {

    // -----------------------------------------------------------------------
    // Test fixtures — 5 items with varied fields
    // -----------------------------------------------------------------------

    /** SKU: "A-100", Name: "Alpha Charger", stock: 5, cost: $5.00, price: $12.00, updated: 2024-03-01 */
    private val itemA = stub(
        id = 1L,
        name = "Alpha Charger",
        sku = "A-100",
        inStock = 5,
        costPriceCents = 500L,
        retailPriceCents = 1200L,
        updatedAt = "2024-03-01 10:00:00",
    )

    /** SKU: "B-050", Name: "Battery Pack Pro", stock: 0, cost: $3.00, price: $8.50, updated: 2024-06-15 */
    private val itemB = stub(
        id = 2L,
        name = "Battery Pack Pro",
        sku = "B-050",
        inStock = 0,
        costPriceCents = 300L,
        retailPriceCents = 850L,
        updatedAt = "2024-06-15 08:00:00",
    )

    /** SKU: "C-200", Name: "Cable USB-C 2m", stock: 42, cost: $1.50, price: $5.99, updated: 2023-11-20 */
    private val itemC = stub(
        id = 3L,
        name = "Cable USB-C 2m",
        sku = "C-200",
        inStock = 42,
        costPriceCents = 150L,
        retailPriceCents = 599L,
        updatedAt = "2023-11-20 09:00:00",
    )

    /** SKU: "D-001", Name: "Display Assembly 6.1in", stock: 3, cost: $45.00, price: $99.99, updated: 2024-01-10 */
    private val itemD = stub(
        id = 4L,
        name = "Display Assembly 6.1in",
        sku = "D-001",
        inStock = 3,
        costPriceCents = 4500L,
        retailPriceCents = 9999L,
        updatedAt = "2024-01-10 12:00:00",
    )

    /** SKU: "E-999", Name: "Ear Speaker Module", stock: 15, cost: $8.00, price: $19.00, updated: 2025-01-01 */
    private val itemE = stub(
        id = 5L,
        name = "Ear Speaker Module",
        sku = "E-999",
        inStock = 15,
        costPriceCents = 800L,
        retailPriceCents = 1900L,
        updatedAt = "2025-01-01 00:00:00",
    )

    private val all = listOf(itemA, itemB, itemC, itemD, itemE)

    // -----------------------------------------------------------------------
    // 1. SkuAZ — sorted by SKU alphabetically case-insensitive
    //    A-100, B-050, C-200, D-001, E-999 → ids: 1, 2, 3, 4, 5
    // -----------------------------------------------------------------------

    @Test
    fun `SkuAZ sort orders by SKU alphabetically`() {
        val sorted = applyInventorySortOrder(all, InventorySort.SkuAZ)
        assertEquals(listOf(1L, 2L, 3L, 4L, 5L), sorted.map { it.id })
    }

    // -----------------------------------------------------------------------
    // 2. NameAZ — sorted by name alphabetically case-insensitive
    //    Alpha, Battery, Cable, Display, Ear → ids: 1, 2, 3, 4, 5
    // -----------------------------------------------------------------------

    @Test
    fun `NameAZ sort orders by name alphabetically`() {
        val sorted = applyInventorySortOrder(all, InventorySort.NameAZ)
        assertEquals(listOf(1L, 2L, 3L, 4L, 5L), sorted.map { it.id })
    }

    // -----------------------------------------------------------------------
    // 3. StockDesc — sorted by inStock descending
    //    C(42), E(15), A(5), D(3), B(0) → ids: 3, 5, 1, 4, 2
    // -----------------------------------------------------------------------

    @Test
    fun `StockDesc sort orders by inStock descending`() {
        val sorted = applyInventorySortOrder(all, InventorySort.StockDesc)
        assertEquals(listOf(3L, 5L, 1L, 4L, 2L), sorted.map { it.id })
    }

    // -----------------------------------------------------------------------
    // 4. LastRestocked — sorted by updatedAt descending (most recent first)
    //    E(2025-01), B(2024-06), A(2024-03), D(2024-01), C(2023-11)
    //    → ids: 5, 2, 1, 4, 3
    // -----------------------------------------------------------------------

    @Test
    fun `LastRestocked sort orders by updatedAt descending`() {
        val sorted = applyInventorySortOrder(all, InventorySort.LastRestocked)
        assertEquals(listOf(5L, 2L, 1L, 4L, 3L), sorted.map { it.id })
    }

    // -----------------------------------------------------------------------
    // 5. PriceAsc — sorted by retailPriceCents ascending
    //    C($5.99), B($8.50), A($12.00), E($19.00), D($99.99)
    //    → ids: 3, 2, 1, 5, 4
    // -----------------------------------------------------------------------

    @Test
    fun `PriceAsc sort orders by retailPriceCents ascending`() {
        val sorted = applyInventorySortOrder(all, InventorySort.PriceAsc)
        assertEquals(listOf(3L, 2L, 1L, 5L, 4L), sorted.map { it.id })
    }

    // -----------------------------------------------------------------------
    // 6. CostAsc — sorted by costPriceCents ascending
    //    C($1.50), B($3.00), A($5.00), E($8.00), D($45.00)
    //    → ids: 3, 2, 1, 5, 4
    // -----------------------------------------------------------------------

    @Test
    fun `CostAsc sort orders by costPriceCents ascending`() {
        val sorted = applyInventorySortOrder(all, InventorySort.CostAsc)
        assertEquals(listOf(3L, 2L, 1L, 5L, 4L), sorted.map { it.id })
    }

    // -----------------------------------------------------------------------
    // 7. Empty list — all sorts return empty without crash
    // -----------------------------------------------------------------------

    @Test
    fun `All sort orders handle empty list`() {
        for (sort in InventorySort.entries) {
            val result = applyInventorySortOrder(emptyList(), sort)
            assertEquals("$sort should return empty list", emptyList<InventoryItemEntity>(), result)
        }
    }

    // -----------------------------------------------------------------------
    // 8. Single item — all sorts return single-element list unchanged
    // -----------------------------------------------------------------------

    @Test
    fun `All sort orders handle single-element list`() {
        for (sort in InventorySort.entries) {
            val result = applyInventorySortOrder(listOf(itemA), sort)
            assertEquals("$sort should return [itemA]", listOf(itemA), result)
        }
    }

    // -----------------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------------

    private fun stub(
        id: Long,
        name: String,
        sku: String,
        inStock: Int,
        costPriceCents: Long,
        retailPriceCents: Long,
        updatedAt: String,
    ) = InventoryItemEntity(
        id = id,
        name = name,
        sku = sku,
        upcCode = null,
        itemType = "part",
        category = null,
        manufacturerId = null,
        manufacturerName = null,
        costPriceCents = costPriceCents,
        retailPriceCents = retailPriceCents,
        inStock = inStock,
        reorderLevel = 5,
        taxClassId = null,
        supplierId = null,
        supplierName = null,
        location = null,
        shelf = null,
        bin = null,
        description = null,
        isSerialize = false,
        createdAt = "2024-01-01 00:00:00",
        updatedAt = updatedAt,
    )
}
