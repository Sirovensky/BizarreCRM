package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

data class RepairServiceItem(
    val id: Long,
    val name: String,
    val slug: String?,
    val category: String?,
    val description: String? = null,
    /**
     * Default labor rate as a plain Double (server stores as REAL, not cents).
     * Use [java.text.NumberFormat.getCurrencyInstance] for display.
     */
    @SerializedName("labor_price")
    val laborPrice: Double = 0.0,
    @SerializedName("is_active")
    val isActive: Int = 1,
    @SerializedName("sort_order")
    val sortOrder: Int = 0,
    @SerializedName("updated_at")
    val updatedAt: String? = null,
)

data class RepairPriceLookup(
    val id: Long?,
    @SerializedName("device_model_id")
    val deviceModelId: Long?,
    @SerializedName("repair_service_id")
    val repairServiceId: Long?,
    @SerializedName("labor_price")
    val laborPrice: Double = 0.0,
    @SerializedName("base_labor_price")
    val baseLaborPrice: Double = 0.0,
    @SerializedName("default_grade")
    val defaultGrade: String? = null,
    val grades: List<RepairPriceGrade> = emptyList()
)

data class RepairPriceGrade(
    val id: Long?,
    val grade: String,
    @SerializedName("grade_label")
    val gradeLabel: String?,
    @SerializedName("part_price")
    val partPrice: Double = 0.0,
    @SerializedName("labor_price_override")
    val laborPriceOverride: Double? = null,
    @SerializedName("effective_labor_price")
    val effectiveLaborPrice: Double = 0.0,
    @SerializedName("is_default")
    val isDefault: Int = 0,
    @SerializedName("inventory_item_name")
    val inventoryItemName: String? = null,
    @SerializedName("inventory_in_stock")
    val inventoryInStock: Int? = null,
    @SerializedName("part_inventory_item_id")
    val partInventoryItemId: Long? = null,
    @SerializedName("catalog_item_name")
    val catalogItemName: String? = null,
    @SerializedName("catalog_url")
    val catalogUrl: String? = null
)
