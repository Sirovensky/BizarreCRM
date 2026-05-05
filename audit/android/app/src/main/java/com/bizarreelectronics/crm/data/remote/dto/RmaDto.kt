package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

// ─── Server response shapes ────────────────────────────────────────────────

/**
 * Flat RMA row as returned by GET /rma (list) and POST /rma (create).
 *
 * Status state machine (server-enforced):
 *   pending → approved | declined
 *   approved → shipped | declined | pending
 *   shipped → received | pending
 *   received → resolved | pending
 *   resolved → (terminal)
 *   declined → (terminal)
 */
data class RmaRow(
    val id: Long,
    @SerializedName("order_id")
    val orderId: String,
    @SerializedName("supplier_id")
    val supplierId: Long?,
    @SerializedName("supplier_name")
    val supplierName: String?,
    val status: String,  // pending|approved|shipped|received|resolved|declined
    val reason: String?,
    val notes: String?,
    @SerializedName("tracking_number")
    val trackingNumber: String?,
    @SerializedName("item_count")
    val itemCount: Int = 0,
    @SerializedName("first_name")
    val createdByFirstName: String?,
    @SerializedName("last_name")
    val createdByLastName: String?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
)

/** Single line item on an RMA (from GET /rma/:id). */
data class RmaItem(
    val id: Long,
    @SerializedName("rma_id")
    val rmaId: Long,
    @SerializedName("inventory_item_id")
    val inventoryItemId: Long?,
    @SerializedName("ticket_device_part_id")
    val ticketDevicePartId: Long?,
    val name: String?,
    @SerializedName("item_name")
    val itemName: String?,
    val sku: String?,
    val quantity: Int = 1,
    val reason: String?,
    val resolution: String?,
)

/** Detail response from GET /rma/:id */
data class RmaDetailData(
    val id: Long,
    @SerializedName("order_id")
    val orderId: String,
    @SerializedName("supplier_id")
    val supplierId: Long?,
    @SerializedName("supplier_name")
    val supplierName: String?,
    val status: String,
    val reason: String?,
    val notes: String?,
    @SerializedName("tracking_number")
    val trackingNumber: String?,
    @SerializedName("created_at")
    val createdAt: String?,
    val items: List<RmaItem> = emptyList(),
)

/** Paginated list wrapper from GET /rma */
data class RmaListData(
    val rmas: List<RmaRow>,
    val pagination: Pagination? = null,
)

// ─── Request bodies ────────────────────────────────────────────────────────

/** Single line item inside a create-RMA request. */
data class RmaItemRequest(
    /** Optional — link to an inventory item for stock restoration on receive. */
    @SerializedName("inventory_item_id")
    val inventoryItemId: Long? = null,
    /** Free-text item name (required when inventory_item_id is null). */
    val name: String? = null,
    val quantity: Int = 1,
    /** Per-item return reason (required by server). */
    val reason: String,
    val resolution: String? = null,
)

/** POST /rma — create a vendor return. */
data class RmaCreateRequest(
    @SerializedName("supplier_id")
    val supplierId: Long? = null,
    @SerializedName("supplier_name")
    val supplierName: String? = null,
    val reason: String? = null,
    val notes: String? = null,
    val items: List<RmaItemRequest>,
)

/** PATCH /rma/:id/status */
data class RmaStatusRequest(
    val status: String,
    @SerializedName("tracking_number")
    val trackingNumber: String? = null,
    val notes: String? = null,
)

/** POST /rma response — returns id + order_id */
data class RmaCreatedData(
    val id: Long,
    @SerializedName("order_id")
    val orderId: String,
)

/** PATCH /rma/:id/status response */
data class RmaStatusData(
    val id: Long,
    val status: String,
)
