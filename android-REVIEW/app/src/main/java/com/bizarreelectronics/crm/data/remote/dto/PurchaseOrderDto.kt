package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

// ─── Server response shapes ────────────────────────────────────────────────

/** Flat PO row as returned by the list and create endpoints. */
data class PurchaseOrderRow(
    val id: Long,
    @SerializedName("order_id")
    val orderId: String,
    @SerializedName("supplier_id")
    val supplierId: Long?,
    @SerializedName("supplier_name")
    val supplierName: String?,
    val status: String,  // draft|pending|ordered|partial|received|cancelled|backordered
    val subtotal: Double,
    val total: Double,
    val notes: String?,
    @SerializedName("expected_date")
    val expectedDate: String?,
    @SerializedName("received_date")
    val receivedDate: String?,
    @SerializedName("actual_received_date")
    val actualReceivedDate: String?,
    @SerializedName("ordered_date")
    val orderedDate: String?,
    @SerializedName("cancelled_date")
    val cancelledDate: String?,
    @SerializedName("cancelled_reason")
    val cancelledReason: String?,
    @SerializedName("paid_status")
    val paidStatus: String?,  // unpaid|partial|paid
    @SerializedName("created_by_name")
    val createdByName: String?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
)

/** PO line-item row (from GET /purchase-orders/:id). */
data class PurchaseOrderItem(
    val id: Long,
    @SerializedName("purchase_order_id")
    val purchaseOrderId: Long,
    @SerializedName("inventory_item_id")
    val inventoryItemId: Long,
    @SerializedName("item_name")
    val itemName: String?,
    val sku: String?,
    @SerializedName("quantity_ordered")
    val quantityOrdered: Int,
    @SerializedName("quantity_received")
    val quantityReceived: Int,
    @SerializedName("cost_price")
    val costPrice: Double,
)

/** Wrapped response from GET /purchase-orders/list */
data class PurchaseOrderListData(
    val orders: List<PurchaseOrderRow>,
    val pagination: Pagination? = null,
)

/** Wrapped response from GET /purchase-orders/:id */
data class PurchaseOrderDetailData(
    val order: PurchaseOrderRow,
    val items: List<PurchaseOrderItem>,
)

// ─── Request bodies ────────────────────────────────────────────────────────

/** Line item for a create PO request. */
data class PurchaseOrderItemRequest(
    @SerializedName("inventory_item_id")
    val inventoryItemId: Long,
    @SerializedName("quantity_ordered")
    val quantityOrdered: Int,
    @SerializedName("cost_price")
    val costPrice: Double,
)

/** POST /purchase-orders */
data class PurchaseOrderCreateRequest(
    @SerializedName("supplier_id")
    val supplierId: Long,
    val notes: String? = null,
    @SerializedName("expected_date")
    val expectedDate: String? = null,
    val items: List<PurchaseOrderItemRequest>,
)

/** PUT /purchase-orders/:id */
data class PurchaseOrderUpdateRequest(
    val status: String? = null,
    val notes: String? = null,
    @SerializedName("expected_date")
    val expectedDate: String? = null,
    @SerializedName("cancelled_reason")
    val cancelledReason: String? = null,
    @SerializedName("paid_status")
    val paidStatus: String? = null,
)

/** Single line item for POST /purchase-orders/:id/receive */
data class PurchaseOrderReceiveItemRequest(
    @SerializedName("purchase_order_item_id")
    val purchaseOrderItemId: Long,
    @SerializedName("quantity_received")
    val quantityReceived: Int,
)

/** POST /purchase-orders/:id/receive */
data class PurchaseOrderReceiveRequest(
    val items: List<PurchaseOrderReceiveItemRequest>,
)

// ─── Supplier list ─────────────────────────────────────────────────────────

/** Flat supplier row (minimal fields needed for the PO supplier picker). */
data class SupplierRow(
    val id: Long,
    val name: String,
    @SerializedName("contact_name")
    val contactName: String?,
    val email: String?,
    val phone: String?,
    @SerializedName("is_active")
    val isActive: Int = 1,
)
// Note: GET /inventory/suppliers/list returns data: [...] (direct array).
// Use ApiResponse<List<SupplierRow>> — no extra wrapper needed.
