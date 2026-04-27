package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

data class InventoryListItem(
    val id: Long,
    val name: String?,
    @SerializedName("item_type")
    val itemType: String?,
    val sku: String?,
    @SerializedName("upc_code")
    val upcCode: String?,
    @SerializedName("in_stock")
    val inStock: Int?,
    @SerializedName("cost_price")
    val costPrice: Double?,
    @SerializedName("retail_price")
    val price: Double?,
    @SerializedName("reorder_level")
    val reorderLevel: Int?,
    @SerializedName("manufacturer_name")
    val manufacturerName: String?,
    @SerializedName("device_name")
    val deviceName: String?,
    @SerializedName("supplier_name")
    val supplierName: String?,
    @SerializedName("is_serialized")
    val isSerialized: Int?,
    @SerializedName("created_at")
    val createdAt: String?
)

data class InventoryDetail(
    val id: Long,
    val name: String?,
    @SerializedName("item_type")
    val itemType: String?,
    val description: String?,
    val sku: String?,
    @SerializedName("upc_code")
    val upcCode: String?,
    @SerializedName("in_stock")
    val inStock: Int?,
    @SerializedName("cost_price")
    val costPrice: Double?,
    @SerializedName("retail_price")
    val price: Double?,
    @SerializedName("tax_class_id")
    val taxClassId: Long?,
    @SerializedName("tax_inclusive")
    val taxInclusive: Int?,
    @SerializedName("manufacturer_id")
    val manufacturerId: Long?,
    @SerializedName("manufacturer_name")
    val manufacturerName: String?,
    @SerializedName("device_model_id")
    val deviceModelId: Long?,
    @SerializedName("device_name")
    val deviceName: String?,
    @SerializedName("supplier_id")
    val supplierId: Long?,
    @SerializedName("supplier_name")
    val supplierName: String?,
    @SerializedName("is_serialized")
    val isSerialized: Int?,
    @SerializedName("reorder_level")
    val reorderLevel: Int?,
    @SerializedName("stock_warning")
    val stockWarning: Int?,
    @SerializedName("valuation_method")
    val valuationMethod: String?,
    val image: String?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
    val serials: List<InventorySerial>?,
    @SerializedName("stock_movements")
    val stockMovements: List<StockMovement>?,
    @SerializedName("group_prices")
    val groupPrices: List<InventoryGroupPrice>?
)

data class InventorySerial(
    val id: Long,
    @SerializedName("serial_number")
    val serialNumber: String?,
    val status: String?,
    @SerializedName("created_at")
    val createdAt: String?
)

data class StockMovement(
    val id: Long,
    val type: String?,
    val quantity: Int?,
    val reason: String?,
    val reference: String?,
    @SerializedName("user_name")
    val userName: String?,
    @SerializedName("created_at")
    val createdAt: String?
)

data class InventoryGroupPrice(
    val id: Long,
    @SerializedName("group_id")
    val groupId: Long?,
    @SerializedName("group_name")
    val groupName: String?,
    val price: Double?
)

data class CreateInventoryRequest(
    val name: String,
    @SerializedName("item_type")
    val itemType: String = "product",
    val description: String? = null,
    val sku: String? = null,
    @SerializedName("upc_code")
    val upcCode: String? = null,
    @SerializedName("in_stock")
    val inStock: Int? = 0,
    @SerializedName("cost_price")
    val costPrice: Double? = null,
    val price: Double? = null,
    @SerializedName("tax_class_id")
    val taxClassId: Long? = null,
    @SerializedName("tax_inclusive")
    val taxInclusive: Int? = 0,
    @SerializedName("manufacturer_id")
    val manufacturerId: Long? = null,
    @SerializedName("device_model_id")
    val deviceModelId: Long? = null,
    @SerializedName("supplier_id")
    val supplierId: Long? = null,
    @SerializedName("is_serialized")
    val isSerialized: Int? = 0,
    @SerializedName("reorder_level")
    val reorderLevel: Int? = null,
    @SerializedName("stock_warning")
    val stockWarning: Int? = 0,
    @SerializedName("valuation_method")
    val valuationMethod: String? = null
)

data class AdjustStockRequest(
    val quantity: Int,
    val type: String,
    val reason: String? = null,
    val reference: String? = null
)

// ─── New DTOs for L1071-L1084 detail panels ─────────────────────────────────

/** One entry in the paginated movement history (L1071). */
data class MovementPage(
    val movements: List<StockMovement>,
    @SerializedName("next_cursor")
    val nextCursor: String?,
    @SerializedName("has_more")
    val hasMore: Boolean,
)

/** One price sample returned by [InventoryApi.getPriceHistory] (L1072). */
data class PriceHistoryPoint(
    @SerializedName("date")
    val date: String,
    @SerializedName("cost_price")
    val costPrice: Double?,
    @SerializedName("retail_price")
    val retailPrice: Double?,
)

data class PriceHistoryData(
    val history: List<PriceHistoryPoint>,
)

/** Sales summary returned by [InventoryApi.getSalesHistory] (L1073). */
data class SalesHistoryData(
    val sold: Int,
    val days: Int,
    val points: List<SalesDayPoint>,
)

data class SalesDayPoint(
    val date: String,
    val qty: Int,
)

/** Supplier detail returned by [InventoryApi.getSupplierDetail] (L1074). */
data class SupplierDetail(
    val id: Long,
    val name: String?,
    val contact: String?,
    val email: String?,
    val phone: String?,
)

data class SupplierDetailData(
    val supplier: SupplierDetail,
)

/** Auto-reorder configuration (L1075). */
data class AutoReorderConfig(
    @SerializedName("reorder_threshold")
    val reorderThreshold: Int,
    @SerializedName("reorder_qty")
    val reorderQty: Int,
    @SerializedName("preferred_supplier")
    val preferredSupplier: String?,
)

data class AutoReorderRequest(
    @SerializedName("reorder_threshold")
    val reorderThreshold: Int,
    @SerializedName("reorder_qty")
    val reorderQty: Int,
    @SerializedName("preferred_supplier")
    val preferredSupplier: String?,
)

/** List of bin locations returned by [InventoryApi.getBins] (L1076). */
data class BinListData(
    val bins: List<String>,
)

/** Ticket usage row returned by [InventoryApi.getUsageInTickets] (L1080). */
data class TicketUsageItem(
    @SerializedName("ticket_id")
    val ticketId: Long,
    @SerializedName("ticket_number")
    val ticketNumber: String?,
    @SerializedName("customer_name")
    val customerName: String?,
    val qty: Int,
    @SerializedName("created_at")
    val createdAt: String?,
)

data class TicketUsageData(
    val tickets: List<TicketUsageItem>,
)

/** Tax class list item (L1082). */
data class TaxClassOption(
    val id: Long,
    val name: String,
    val rate: Double,
    @SerializedName("is_default")
    val isDefault: Int? = null,
)

data class TaxClassOptionsData(
    @SerializedName("tax_classes")
    val taxClasses: List<TaxClassOption>,
)

/** Photo metadata returned by the photos endpoint (L1083). */
data class InventoryPhoto(
    val id: Long,
    val url: String,
    @SerializedName("created_at")
    val createdAt: String?,
)

data class PhotoListData(
    val photos: List<InventoryPhoto>,
)

// ─── §6.7 Purchase Order DTOs ────────────────────────────────────────────────

data class PurchaseOrderRow(
    val id: Long,
    @SerializedName("order_id") val orderId: String?,
    @SerializedName("supplier_id") val supplierId: Long?,
    @SerializedName("supplier_name") val supplierName: String?,
    val status: String?,
    val subtotal: Double?,
    val total: Double?,
    val notes: String?,
    @SerializedName("expected_date") val expectedDate: String?,
    @SerializedName("created_at") val createdAt: String?,
    @SerializedName("created_by_name") val createdByName: String?,
)

data class PurchaseOrderListData(
    val orders: List<PurchaseOrderRow>,
    val pagination: PoPagination?,
)

data class PoPagination(
    val page: Int,
    @SerializedName("per_page") val perPage: Int,
    val total: Int,
    @SerializedName("total_pages") val totalPages: Int,
)

data class PurchaseOrderItem(
    val id: Long,
    @SerializedName("inventory_item_id") val inventoryItemId: Long?,
    @SerializedName("item_name") val itemName: String?,
    val sku: String?,
    @SerializedName("quantity_ordered") val quantityOrdered: Int,
    @SerializedName("quantity_received") val quantityReceived: Int,
    @SerializedName("cost_price") val costPrice: Double?,
)

data class PurchaseOrderDetail(
    val id: Long,
    @SerializedName("order_id") val orderId: String?,
    @SerializedName("supplier_id") val supplierId: Long?,
    @SerializedName("supplier_name") val supplierName: String?,
    val status: String?,
    val subtotal: Double?,
    val total: Double?,
    val notes: String?,
    @SerializedName("expected_date") val expectedDate: String?,
    @SerializedName("created_at") val createdAt: String?,
    val items: List<PurchaseOrderItem>?,
)

data class PurchaseOrderDetailData(
    val po: PurchaseOrderDetail?,
    // Server may return the PO directly at the top level
    val id: Long? = null,
    @SerializedName("order_id") val orderId: String? = null,
    val status: String? = null,
)

data class CreatePoLineItem(
    @SerializedName("inventory_item_id") val inventoryItemId: Long,
    @SerializedName("quantity_ordered") val quantityOrdered: Int,
    @SerializedName("cost_price") val costPrice: Double?,
)

data class CreatePurchaseOrderRequest(
    @SerializedName("supplier_id") val supplierId: Long,
    val notes: String? = null,
    @SerializedName("expected_date") val expectedDate: String? = null,
    val items: List<CreatePoLineItem> = emptyList(),
)

data class UpdatePurchaseOrderRequest(
    val status: String? = null,
    val notes: String? = null,
    @SerializedName("expected_date") val expectedDate: String? = null,
)

data class ReceivePoItem(
    @SerializedName("purchase_order_item_id") val purchaseOrderItemId: Long,
    @SerializedName("quantity_received") val quantityReceived: Int,
)

data class ReceivePurchaseOrderRequest(
    val items: List<ReceivePoItem>,
)

data class SupplierListItem(
    val id: Long,
    val name: String?,
    val email: String?,
    val phone: String?,
    @SerializedName("is_active") val isActive: Int?,
)
