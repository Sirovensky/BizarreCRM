package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.bizarreelectronics.crm.util.toDollars

/**
 * Inventory item row.
 *
 * @audit-fixed: Section 33 / D1 — `cost_price` and `retail_price` were previously
 * REAL columns mapped to Kotlin `Double`. That meant every inventory item carried
 * IEEE-754 rounding drift identical to the bug fixed for tickets/invoices in
 * Migration 2→3. Migration 3→4 converts both to **Long cents** (1234 = $12.34) and
 * the entity now stores [costPriceCents] / [retailPriceCents]. The legacy
 * [costPrice] / [retailPrice] Doubles are preserved as `@Ignore`d compatibility
 * shims so existing UI code (`InventoryListScreen`, `InventoryDetailScreen`,
 * `InventoryEditScreen`) continues to compile against `String.format("$%.2f", ...)`
 * without an immediate rewrite.
 *
 * Migration 3→4 lives in [com.bizarreelectronics.crm.data.local.db.Migrations].
 * Indices on `sku`, `upc_code`, and `manufacturer_id` were added at the same
 * time so list/search queries no longer require a full table scan.
 */
@Entity(
    tableName = "inventory_items",
    indices = [
        Index("sku"),
        Index("upc_code"),
        Index("manufacturer_id"),
    ],
)
data class InventoryItemEntity(
    @PrimaryKey
    val id: Long,

    val name: String,

    val sku: String?,

    @ColumnInfo(name = "upc_code")
    val upcCode: String?,

    @ColumnInfo(name = "item_type")
    val itemType: String?,

    val category: String?,

    @ColumnInfo(name = "manufacturer_id")
    val manufacturerId: Long?,

    @ColumnInfo(name = "manufacturer_name")
    val manufacturerName: String?,

    /** Cents. 1234 = $12.34. @audit-fixed: was REAL/Double — see class doc. */
    @ColumnInfo(name = "cost_price_cents")
    val costPriceCents: Long = 0L,

    /** Cents. 1234 = $12.34. @audit-fixed: was REAL/Double — see class doc. */
    @ColumnInfo(name = "retail_price_cents")
    val retailPriceCents: Long = 0L,

    @ColumnInfo(name = "in_stock")
    val inStock: Int = 0,

    @ColumnInfo(name = "reorder_level")
    val reorderLevel: Int = 0,

    @ColumnInfo(name = "tax_class_id")
    val taxClassId: Long?,

    @ColumnInfo(name = "supplier_id")
    val supplierId: Long?,

    @ColumnInfo(name = "supplier_name")
    val supplierName: String?,

    val location: String?,

    val shelf: String?,

    val bin: String?,

    val description: String?,

    @ColumnInfo(name = "is_serialize")
    val isSerialize: Boolean = false,

    @ColumnInfo(name = "created_at")
    val createdAt: String,

    @ColumnInfo(name = "updated_at")
    val updatedAt: String,

    @ColumnInfo(name = "locally_modified")
    val locallyModified: Boolean = false,
)

// ─── Backward-compat shims for the old Double API ──────────────────────────────
//
// @audit-fixed: Section 33 / D1 — keep these so InventoryListScreen / DetailScreen
// / EditScreen continue to compile while still reading from the new Long-cents
// columns under the hood. New code should prefer [InventoryItemEntity.costPriceCents]
// / [InventoryItemEntity.retailPriceCents] together with [Long.formatAsMoney] from
// `util/Money.kt`. The Double accessors are deprecated to nudge migration.

@Deprecated(
    "Use costPriceCents (Long) + Long.formatAsMoney() to avoid IEEE-754 drift.",
    ReplaceWith("costPriceCents.toDollars()", imports = ["com.bizarreelectronics.crm.util.toDollars"]),
)
val InventoryItemEntity.costPrice: Double
    get() = costPriceCents.toDollars()

@Deprecated(
    "Use retailPriceCents (Long) + Long.formatAsMoney() to avoid IEEE-754 drift.",
    ReplaceWith("retailPriceCents.toDollars()", imports = ["com.bizarreelectronics.crm.util.toDollars"]),
)
val InventoryItemEntity.retailPrice: Double
    get() = retailPriceCents.toDollars()
