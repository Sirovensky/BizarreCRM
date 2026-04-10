package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

data class EstimateListData(
    val estimates: List<EstimateListItem>,
    val pagination: Pagination? = null
)

data class EstimateListItem(
    val id: Long,
    @SerializedName("order_id")
    val orderId: String?,
    @SerializedName("customer_id")
    val customerId: Long?,
    @SerializedName("customer_first_name")
    val customerFirstName: String?,
    @SerializedName("customer_last_name")
    val customerLastName: String?,
    val status: String?,
    val total: Double?,
    @SerializedName("valid_until")
    val validUntil: String?,
    @SerializedName("created_at")
    val createdAt: String?,
) {
    val customerName: String
        get() = listOfNotNull(customerFirstName, customerLastName).joinToString(" ").ifBlank { "Unknown" }
}

data class EstimateDetail(
    val id: Long,
    @SerializedName("order_id")
    val orderId: String?,
    @SerializedName("customer_id")
    val customerId: Long?,
    @SerializedName("customer_first_name")
    val customerFirstName: String?,
    @SerializedName("customer_last_name")
    val customerLastName: String?,
    @SerializedName("customer_email")
    val customerEmail: String?,
    @SerializedName("customer_phone")
    val customerPhone: String?,
    val status: String?,
    val discount: Double?,
    val notes: String?,
    @SerializedName("valid_until")
    val validUntil: String?,
    val subtotal: Double?,
    @SerializedName("total_tax")
    val totalTax: Double?,
    val total: Double?,
    @SerializedName("created_by")
    val createdBy: Long?,
    @SerializedName("created_by_first_name")
    val createdByFirstName: String?,
    @SerializedName("created_by_last_name")
    val createdByLastName: String?,
    @SerializedName("is_deleted")
    val isDeleted: Boolean?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
    @SerializedName("sent_at")
    val sentAt: String?,
    @SerializedName("approved_at")
    val approvedAt: String?,
    @SerializedName("converted_ticket_id")
    val convertedTicketId: Long?,
    @SerializedName("line_items")
    val lineItems: List<EstimateLineItem>?,
) {
    val customerName: String
        get() = listOfNotNull(customerFirstName, customerLastName).joinToString(" ").ifBlank { "Unknown" }
    val createdByName: String?
        get() = listOfNotNull(createdByFirstName, createdByLastName).joinToString(" ").ifBlank { null }
}

data class EstimateLineItem(
    val id: Long,
    @SerializedName("estimate_id")
    val estimateId: Long?,
    @SerializedName("inventory_item_id")
    val inventoryItemId: Long?,
    val description: String?,
    val quantity: Int?,
    @SerializedName("unit_price")
    val unitPrice: Double?,
    @SerializedName("tax_amount")
    val taxAmount: Double?,
    val total: Double?,
    @SerializedName("item_name")
    val itemName: String?,
    @SerializedName("item_sku")
    val itemSku: String?,
)

data class CreateEstimateRequest(
    @SerializedName("customer_id")
    val customerId: Long?,
    val discount: Double? = null,
    val notes: String? = null,
    @SerializedName("valid_until")
    val validUntil: String? = null,
    @SerializedName("line_items")
    val lineItems: List<CreateEstimateLineItem>,
)

data class CreateEstimateLineItem(
    @SerializedName("inventory_item_id")
    val inventoryItemId: Long? = null,
    val description: String? = null,
    val quantity: Int = 1,
    @SerializedName("unit_price")
    val unitPrice: Double = 0.0,
    @SerializedName("tax_class_id")
    val taxClassId: Long? = null,
)

data class UpdateEstimateRequest(
    @SerializedName("customer_id")
    val customerId: Long? = null,
    val status: String? = null,
    val discount: Double? = null,
    val notes: String? = null,
    @SerializedName("valid_until")
    val validUntil: String? = null,
    @SerializedName("line_items")
    val lineItems: List<CreateEstimateLineItem>? = null,
)
