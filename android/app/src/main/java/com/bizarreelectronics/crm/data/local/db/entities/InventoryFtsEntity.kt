package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Fts4

/**
 * FTS4 virtual table shadowing [InventoryItemEntity] for prefix-aware full-text search.
 *
 * Mirrors the text columns most useful for parts/inventory search:
 *  - [name] — part name (e.g. "iPhone 14 Screen")
 *  - [sku] — SKU code
 *  - [upcCode] — UPC barcode string
 *  - [category] — category label
 *  - [manufacturerName] — denormalized manufacturer name
 *  - [supplierName] — denormalized supplier name
 *  - [description] — free-text description
 *
 * Sync strategy: AFTER INSERT / AFTER UPDATE / AFTER DELETE triggers on
 * `inventory_items` (added in MIGRATION_11_12) keep this table current.
 */
@Fts4(contentEntity = InventoryItemEntity::class)
@Entity(tableName = "inventory_fts")
data class InventoryFtsEntity(
    val name: String,
    val sku: String?,
    @ColumnInfo(name = "upc_code")         val upcCode: String?,
    val category: String?,
    @ColumnInfo(name = "manufacturer_name") val manufacturerName: String?,
    @ColumnInfo(name = "supplier_name")    val supplierName: String?,
    val description: String?,
)
