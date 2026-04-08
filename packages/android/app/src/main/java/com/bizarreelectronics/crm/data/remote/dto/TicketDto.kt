package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

/** Nested customer in ticket list response */
data class TicketCustomerRef(
    val id: Long?,
    @SerializedName("first_name")
    val firstName: String?,
    @SerializedName("last_name")
    val lastName: String?,
    val phone: String?,
    val mobile: String?,
    val email: String?,
    val organization: String?,
) {
    val fullName: String get() = listOfNotNull(firstName, lastName).joinToString(" ").ifBlank { organization ?: "Unknown" }
}

/** First device summary in ticket list */
data class TicketFirstDevice(
    @SerializedName("device_name")
    val deviceName: String?,
    @SerializedName("device_type")
    val deviceType: String?,
    @SerializedName("service_name")
    val serviceName: String?,
    val imei: String?,
    val serial: String?,
    @SerializedName("additional_notes")
    val additionalNotes: String?,
)

data class TicketListItem(
    val id: Long,
    @SerializedName("order_id")
    val orderId: String,
    @SerializedName("customer_id")
    val customerId: Long?,
    // Server returns nested objects, not flat fields
    val customer: TicketCustomerRef?,
    val status: TicketStatusObj?,
    @SerializedName("assigned_user")
    val assignedUser: UserRef?,
    @SerializedName("first_device")
    val firstDevice: TicketFirstDevice?,
    @SerializedName("device_count")
    val deviceCount: Int?,
    val total: Double?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
    @SerializedName("is_pinned")
    val isPinned: Boolean?,
    @SerializedName("latest_internal_note")
    val latestInternalNote: String?,
) {
    val customerName: String get() = customer?.fullName ?: "Unknown"
    val customerPhone: String? get() = customer?.mobile ?: customer?.phone
    val statusName: String? get() = status?.name
    val statusColor: String? get() = status?.color
    val assignedName: String? get() = assignedUser?.fullName
    // For compat with code expecting devices list
    val devices: List<TicketDeviceSummary>?
        get() = firstDevice?.let { listOf(TicketDeviceSummary(0, it.deviceName, it.deviceName, null, null, null)) }
}

data class TicketDeviceSummary(
    val id: Long,
    val name: String?,
    @SerializedName("device_name")
    val deviceName: String?,
    val imei: String?,
    val serial: String?,
    @SerializedName("status")
    val status: String?
)

/** Nested status object from ticket detail */
data class TicketStatusObj(
    val id: Long,
    val name: String?,
    val color: String?,
    @SerializedName("is_closed")
    val isClosed: Int?,
    @SerializedName("is_cancelled")
    val isCancelled: Int?,
)

/** Nested user reference from ticket detail */
data class UserRef(
    val id: Long,
    @SerializedName("first_name")
    val firstName: String?,
    @SerializedName("last_name")
    val lastName: String?,
    @SerializedName("avatar_url")
    val avatarUrl: String?,
) {
    val fullName: String get() = listOfNotNull(firstName, lastName).joinToString(" ").ifBlank { "Unknown" }
}

data class TicketDetail(
    val id: Long,
    @SerializedName("order_id")
    val orderId: String,
    @SerializedName("customer_id")
    val customerId: Long?,
    val customer: CustomerListItem?,
    @SerializedName("status_id")
    val statusId: Long,
    // Server returns nested status object
    val status: TicketStatusObj?,
    val subtotal: Double?,
    val discount: Double?,
    @SerializedName("discount_reason")
    val discountReason: String?,
    @SerializedName("total_tax")
    val totalTax: Double?,
    val total: Double?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
    @SerializedName("created_by")
    val createdBy: Long?,
    @SerializedName("assigned_to")
    val assignedTo: Long?,
    @SerializedName("assigned_user")
    val assignedUser: UserRef?,
    @SerializedName("created_by_user")
    val createdByUser: UserRef?,
    @SerializedName("how_did_u_find_us")
    val howDidUFindUs: String?,
    val signature: String?,
    @SerializedName("is_pinned")
    val isPinned: Boolean?,
    @SerializedName("is_starred")
    val isStarred: Boolean?,
    @SerializedName("invoice_id")
    val invoiceId: Long?,
    val devices: List<TicketDevice>?,
    val notes: List<TicketNote>?,
    val history: List<TicketHistory>?,
    val photos: List<TicketPhoto>?,
    val payments: List<PaymentSummary>?,
) {
    /** Computed helpers for UI compatibility */
    val statusName: String? get() = status?.name
    val statusColor: String? get() = status?.color
    val assignedName: String? get() = assignedUser?.fullName
}

data class TicketDevice(
    val id: Long,
    @SerializedName("ticket_id")
    val ticketId: Long,
    val name: String?,
    @SerializedName("device_model_id")
    val deviceModelId: Long?,
    @SerializedName("device_name")
    val deviceName: String?,
    @SerializedName("manufacturer_name")
    val manufacturerName: String?,
    val category: String?,
    val imei: String?,
    val serial: String?,
    @SerializedName("security_code")
    val securityCode: String?,
    val color: String?,
    // Server returns nested status object { id, name, color }
    val status: TicketStatusObj?,
    @SerializedName("assigned_to")
    val assignedTo: Long?,
    @SerializedName("assigned_user")
    val assignedUser: UserRef?,
    @SerializedName("due_on")
    val dueOn: String?,
    val warranty: Int?,
    @SerializedName("warranty_days")
    val warrantyDays: Int?,
    val price: Double?,
    @SerializedName("line_discount")
    val lineDiscount: Double?,
    @SerializedName("tax_amount")
    val taxAmount: Double?,
    @SerializedName("tax_class_id")
    val taxClassId: Long?,
    val total: Double?,
    @SerializedName("additional_notes")
    val additionalNotes: String?,
    @SerializedName("customer_comments")
    val customerComments: String?,
    @SerializedName("staff_comments")
    val staffComments: String?,
    // Server returns either [] (array of strings) or {} (object with boolean checks)
    @SerializedName("pre_conditions")
    val preConditions: @JvmSuppressWildcards Any?,
    @SerializedName("post_conditions")
    val postConditions: @JvmSuppressWildcards Any?,
    val parts: List<TicketDevicePart>?,
    val photos: List<TicketPhoto>?,
    val service: Map<String, @JvmSuppressWildcards Any?>?,
) {
    val statusName: String? get() = status?.name
    val statusColor: String? get() = status?.color

    /** Convert pre_conditions (array or object) to displayable list */
    val preConditionsList: List<String> get() = conditionsToList(preConditions)
    val postConditionsList: List<String> get() = conditionsToList(postConditions)
}

/** Converts either ["scratch","dent"] or {"power":true,"screen":false} to a flat string list */
private fun conditionsToList(value: Any?): List<String> {
    if (value == null) return emptyList()
    return when (value) {
        is List<*> -> value.filterIsInstance<String>()
        is Map<*, *> -> value.entries
            .filter { (it.value as? Boolean) == true || it.value == 1.0 }
            .map { it.key.toString().replace("_", " ").replaceFirstChar { c -> c.uppercase() } }
        else -> emptyList()
    }
}

data class TicketDevicePart(
    val id: Long,
    @SerializedName("ticket_device_id")
    val ticketDeviceId: Long,
    @SerializedName("inventory_item_id")
    val inventoryItemId: Long?,
    val name: String?,
    val sku: String?,
    val quantity: Int?,
    val price: Double?,
    val total: Double?,
    val status: String?,
    @SerializedName("catalog_item_id")
    val catalogItemId: Long?,
    @SerializedName("supplier_url")
    val supplierUrl: String?
)

data class TicketNote(
    val id: Long,
    @SerializedName("ticket_id")
    val ticketId: Long,
    val type: String?,
    @SerializedName("user_id")
    val userId: Long?,
    // Server returns nested user object, not flat user_name
    val user: UserRef?,
    val content: String?,
    val image: String?,
    @SerializedName("is_flagged")
    val isFlagged: Boolean?,
    @SerializedName("device_id")
    val deviceId: Long?,
    @SerializedName("device_name")
    val deviceName: String?,
    @SerializedName("parent_id")
    val parentId: Long?,
    @SerializedName("created_at")
    val createdAt: String?,
) {
    val userName: String? get() = user?.fullName
    val msgText: String? get() = content
}

data class TicketHistory(
    val id: Long,
    @SerializedName("ticket_id")
    val ticketId: Long,
    val description: String?,
    @SerializedName("user_id")
    val userId: Long?,
    @SerializedName("user_name")
    val userName: String?,
    @SerializedName("created_at")
    val createdAt: String?
)

data class TicketPhoto(
    val id: Long,
    @SerializedName("ticket_id")
    val ticketId: Long,
    @SerializedName("device_id")
    val deviceId: Long?,
    val type: String?,
    val url: String?,
    @SerializedName("file_name")
    val fileName: String?,
    @SerializedName("created_at")
    val createdAt: String?
)

data class PaymentSummary(
    val id: Long,
    val amount: Double?,
    val method: String?,
    @SerializedName("payment_date")
    val paymentDate: String?,
    @SerializedName("transaction_id")
    val transactionId: String?,
    val notes: String?
)

data class CreateTicketRequest(
    @SerializedName("customer_id")
    val customerId: Long?,
    @SerializedName("status_id")
    val statusId: Long? = null,
    @SerializedName("assigned_to")
    val assignedTo: Long? = null,
    @SerializedName("how_did_u_find_us")
    val howDidUFindUs: String? = null,
    val discount: Double? = null,
    @SerializedName("discount_reason")
    val discountReason: String? = null,
    val source: String? = null,
    val devices: List<CreateTicketDeviceRequest>
)

data class CreateTicketDeviceRequest(
    @SerializedName("device_name")
    val name: String? = null,
    @SerializedName("device_model_id")
    val deviceModelId: Long? = null,
    @SerializedName("device_type")
    val deviceType: String? = null,
    val category: String? = null,
    val imei: String? = null,
    val serial: String? = null,
    @SerializedName("security_code")
    val securityCode: String? = null,
    val color: String? = null,
    val network: String? = null,
    @SerializedName("service_name")
    val serviceName: String? = null,
    @SerializedName("service_id")
    val serviceId: Long? = null,
    @SerializedName("assigned_to")
    val assignedTo: Long? = null,
    @SerializedName("due_on")
    val dueOn: String? = null,
    val warranty: Boolean? = null,
    @SerializedName("warranty_days")
    val warrantyDays: Int? = null,
    @SerializedName("warranty_timeframe")
    val warrantyTimeframe: String? = null,
    val price: Double? = null,
    @SerializedName("line_discount")
    val lineDiscount: Double? = null,
    @SerializedName("tax_class_id")
    val taxClassId: Long? = null,
    @SerializedName("device_location")
    val deviceLocation: String? = null,
    @SerializedName("additional_notes")
    val additionalNotes: String? = null,
    @SerializedName("customer_comments")
    val customerComments: String? = null,
    @SerializedName("staff_comments")
    val staffComments: String? = null,
    @SerializedName("pre_conditions")
    val preConditions: List<String>? = null,
    val parts: List<CreateTicketPartRequest>? = null
)

data class CreatePartRequest(
    @SerializedName("inventory_item_id")
    val inventoryItemId: Long? = null,
    val name: String,
    val price: Double = 0.0,
    val quantity: Int = 1,
)

data class CreateTicketPartRequest(
    @SerializedName("inventory_item_id")
    val inventoryItemId: Long? = null,
    val name: String? = null,
    val quantity: Int = 1,
    val price: Double? = null,
    @SerializedName("catalog_item_id")
    val catalogItemId: Long? = null,
    @SerializedName("supplier_url")
    val supplierUrl: String? = null
)

data class UpdateTicketRequest(
    @SerializedName("customer_id")
    val customerId: Long? = null,
    @SerializedName("status_id")
    val statusId: Long? = null,
    @SerializedName("assigned_to")
    val assignedTo: Long? = null,
    @SerializedName("how_did_u_find_us")
    val howDidUFindUs: String? = null,
    val discount: Double? = null,
    @SerializedName("discount_reason")
    val discountReason: String? = null,
    @SerializedName("is_pinned")
    val isPinned: Boolean? = null,
    @SerializedName("is_starred")
    val isStarred: Boolean? = null,
    @SerializedName("_updated_at")
    val updatedAt: String? = null,
    val devices: List<CreateTicketDeviceRequest>? = null
)
