package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "inventory_items")
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

    @ColumnInfo(name = "cost_price")
    val costPrice: Double = 0.0,

    @ColumnInfo(name = "retail_price")
    val retailPrice: Double = 0.0,

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
