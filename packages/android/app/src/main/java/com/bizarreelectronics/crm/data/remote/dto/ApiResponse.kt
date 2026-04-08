@file:Suppress("unused")

package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

data class ApiResponse<T>(
    val success: Boolean,
    val data: T?,
    val message: String? = null
)

data class Pagination(
    val page: Int,
    @SerializedName("per_page")
    val perPage: Int,
    val total: Int,
    @SerializedName("total_pages")
    val totalPages: Int
)

// ─── List response wrappers matching server's { data: { <key>: [...], pagination } } ───

data class TicketListData(
    val tickets: List<TicketListItem>,
    @SerializedName("status_counts")
    val statusCounts: List<Map<String, @JvmSuppressWildcards Any>>? = null,
    val pagination: Pagination? = null
)

data class CustomerListData(
    val customers: List<CustomerListItem>,
    val pagination: Pagination? = null
)

data class InvoiceListData(
    val invoices: List<InvoiceListItem>,
    val pagination: Pagination? = null
)

data class InventoryListData(
    val items: List<InventoryListItem>,
    val pagination: Pagination? = null
)

data class InvoiceDetailData(
    val invoice: InvoiceDetail
)

data class InventoryDetailData(
    val item: InventoryDetail,
    val movements: List<StockMovement>? = null,
    @SerializedName("group_prices")
    val groupPrices: List<InventoryGroupPrice>? = null
)

data class NotificationListData(
    val notifications: List<NotificationItem>,
    val pagination: Pagination? = null
)

data class NotificationItem(
    val id: Long,
    @SerializedName("user_id")
    val userId: Long?,
    val type: String?,
    val title: String?,
    val message: String?,
    @SerializedName("entity_type")
    val entityType: String?,
    @SerializedName("entity_id")
    val entityId: Long?,
    @SerializedName("is_read")
    val isRead: Int,
    @SerializedName("created_at")
    val createdAt: String?
)

data class UnreadCountData(
    val count: Int
)

data class SmsConversationListData(
    val conversations: List<SmsConversationItem>
)

data class SmsConversationItem(
    @SerializedName("conv_phone")
    val convPhone: String,
    @SerializedName("last_message_at")
    val lastMessageAt: String?,
    @SerializedName("last_message")
    val lastMessage: String?,
    @SerializedName("last_direction")
    val lastDirection: String?,
    @SerializedName("message_count")
    val messageCount: Int,
    @SerializedName("unread_count")
    val unreadCount: Int,
    val customer: CustomerListItem?,
    @SerializedName("recent_ticket")
    val recentTicket: Map<String, @JvmSuppressWildcards Any>?,
    @SerializedName("is_flagged")
    val isFlagged: Boolean,
    @SerializedName("is_pinned")
    val isPinned: Boolean
)

data class SmsThreadData(
    val messages: List<SmsMessageItem>,
    val customer: CustomerListItem?,
    @SerializedName("recent_tickets")
    val recentTickets: List<Map<String, @JvmSuppressWildcards Any>>?
)

data class SmsMessageItem(
    val id: Long,
    @SerializedName("from_number")
    val fromNumber: String?,
    @SerializedName("to_number")
    val toNumber: String?,
    @SerializedName("conv_phone")
    val convPhone: String?,
    val message: String?,
    val status: String?,
    val direction: String?,
    @SerializedName("message_type")
    val messageType: String?,
    @SerializedName("created_at")
    val createdAt: String?
)

data class TaxClassListData(
    @SerializedName("tax_classes")
    val taxClasses: List<TaxClassItem>
)

data class TaxClassItem(
    val id: Long,
    val name: String,
    val rate: Double,
    @SerializedName("is_default")
    val isDefault: Int
)

data class StatusListData(
    val statuses: List<TicketStatusItem>
)

data class TicketStatusItem(
    val id: Long,
    val name: String,
    val color: String?,
    @SerializedName("sort_order")
    val sortOrder: Int,
    @SerializedName("is_closed")
    val isClosed: Int,
    @SerializedName("is_cancelled")
    val isCancelled: Int,
    @SerializedName("notify_customer")
    val notifyCustomer: Int
)

data class EmployeeListItem(
    val id: Long,
    val username: String?,
    val email: String?,
    @SerializedName("first_name")
    val firstName: String?,
    @SerializedName("last_name")
    val lastName: String?,
    val role: String?,
    @SerializedName("avatar_url")
    val avatarUrl: String?,
    @SerializedName("is_active")
    val isActive: Int,
    @SerializedName("has_pin")
    val hasPin: Int,
    val permissions: String?,
    @SerializedName("is_clocked_in")
    val isClockedIn: Boolean? = null,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?
)
