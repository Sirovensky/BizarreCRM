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

/**
 * Cursor-based page response used by [TicketRemoteMediator] (plan:L632).
 *
 * The server returns the same ticket list but with an opaque [cursor] token for the
 * next page and a [serverExhausted] flag confirming no further pages exist.
 * When the server does not yet support cursor params it falls back to returning
 * the standard ticket array under the `tickets` key — callers should handle [cursor]=null
 * as end-of-pagination.
 */
data class TicketPageResponse(
    /** Page of ticket items. */
    val tickets: List<TicketListItem> = emptyList(),
    /** Opaque cursor to pass as `?cursor=` on the next APPEND load. Null = exhausted. */
    val cursor: String? = null,
    /** True when the server explicitly confirms no more pages remain. */
    @SerializedName("server_exhausted")
    val serverExhausted: Boolean = false,
    /** Optional approximate total for UI display ("Showing N of ~M"). */
    val total: Int? = null,
)

data class CustomerListData(
    val customers: List<CustomerListItem>,
    val pagination: Pagination? = null
)

/**
 * Cursor-based page response for [CustomerRemoteMediator] (plan:L874).
 * Mirrors [TicketPageResponse] exactly.
 */
data class CustomerPageResponse(
    val customers: List<CustomerListItem> = emptyList(),
    val cursor: String? = null,
    @SerializedName("server_exhausted")
    val serverExhausted: Boolean = false,
    val total: Int? = null,
)

/**
 * Cursor-based page response for [EstimateListViewModel] offline-first paging (plan:L1325).
 *
 * Mirrors [TicketPageResponse] exactly. When the server does not yet support cursor params
 * it falls back to returning the standard estimate array under the `estimates` key; callers
 * treat [cursor]=null as end-of-pagination.
 */
data class EstimatePageResponse(
    val estimates: List<EstimateListItem> = emptyList(),
    /** Opaque cursor to pass as `?cursor=` on the next APPEND load. Null = exhausted. */
    val cursor: String? = null,
    /** True when the server explicitly confirms no more pages remain. */
    @SerializedName("server_exhausted")
    val serverExhausted: Boolean = false,
    /** Optional approximate total for UI display. */
    val total: Int? = null,
)

/** Stats tiles for the customer list header (plan:L880). */
data class CustomerStats(
    val total: Int = 0,
    val vips: Int = 0,
    @SerializedName("at_risk")
    val atRisk: Int = 0,
    @SerializedName("total_ltv")
    val totalLtv: Double = 0.0,
    @SerializedName("avg_ltv")
    val avgLtv: Double = 0.0,
)

/**
 * A single component contributing to the health score.
 * Server may omit the field entirely when the health-score endpoint is not
 * yet implemented; callers treat a null/empty list as "no breakdown available".
 */
data class HealthScoreComponent(
    val name: String,
    val score: Int = 0,
    @SerializedName("max_score")
    val maxScore: Int = 100,
    val explanation: String? = null,
)

/** Health score from GET /customers/:id/health-score (plan:L892). */
data class CustomerHealthScore(
    val score: Int = 0,
    val tier: String? = null,
    val explanation: String? = null,
    @SerializedName("last_calculated_at")
    val lastCalculatedAt: String? = null,
    /** Breakdown by component (Recency / Frequency / Spend / Engagement). Null = server doesn't return breakdown yet. */
    val components: List<HealthScoreComponent>? = null,
)

/** Churn-risk list from GET /reports/churn-risk (§45.3). */
data class ChurnRiskData(
    @SerializedName("at_risk_count")
    val atRiskCount: Int = 0,
    @SerializedName("customers")
    val customers: List<ChurnRiskCustomer> = emptyList(),
)

/** A single at-risk customer entry from GET /reports/churn-risk. */
data class ChurnRiskCustomer(
    val id: Long,
    @SerializedName("first_name")
    val firstName: String?,
    @SerializedName("last_name")
    val lastName: String?,
    val phone: String?,
    val mobile: String?,
    @SerializedName("days_since_last_visit")
    val daysSinceLastVisit: Int?,
    @SerializedName("lifetime_value_cents")
    val lifetimeValueCents: Long?,
)

/** LTV tier from GET /customers/:id/ltv-tier (plan:L893). */
data class CustomerLtvTier(
    val tier: String = "Regular",
    val explanation: String? = null,
    @SerializedName("lifetime_value")
    val lifetimeValue: Double = 0.0,
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
    val isPinned: Boolean,
    // L1510 — sentiment badge; null when server doesn't return the field
    @SerializedName("sentiment")
    val sentiment: String? = null,
    // L1511 — archive filter support
    @SerializedName("is_archived")
    val isArchived: Boolean = false,
    // L1512 — assign filter support
    @SerializedName("assigned_to")
    val assignedTo: String? = null,
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
    val notifyCustomer: Int,
    /** L740 — transition guards; server returns list like ["note_added","photos_taken"]. */
    @SerializedName("transition_requirements")
    val transitionRequirements: List<String> = emptyList(),
    /** L739 — group label for grouping statuses in pickers (e.g. "open", "closed"). */
    val group: String? = null,
    /** L738 — sort order within group. */
    val order: Int = sortOrder,
)

// ─── L725 — Warranty lookup result ───────────────────────────────────────────

/**
 * Single warranty-lookup row from GET /api/v1/tickets/warranty-lookup.
 *
 * Server computes [warrantyActive] = (warrantyExpires >= today) and returns it;
 * [customerFirst] + [customerLast] are the matching customer's name parts.
 * The old WarrantyResult fields (customerName, status, purchaseDate, warrantyEnd,
 * lastRepairDate) did not match server columns and have been replaced.
 */
data class WarrantyResult(
    @SerializedName("ticket_id")
    val ticketId: Long?,
    @SerializedName("order_id")
    val orderId: String?,
    @SerializedName("device_name")
    val deviceName: String?,
    val imei: String?,
    val serial: String?,
    @SerializedName("warranty_days")
    val warrantyDays: Int?,
    @SerializedName("warranty_expires")
    val warrantyExpires: String?,
    @SerializedName("warranty_active")
    val warrantyActive: Boolean?,
    @SerializedName("customer_first")
    val customerFirst: String?,
    @SerializedName("customer_last")
    val customerLast: String?,
    @SerializedName("status_name")
    val statusName: String?,
    @SerializedName("collected_date")
    val collectedDate: String?,
    @SerializedName("ticket_created")
    val ticketCreated: String?,
) {
    val customerName: String get() = listOfNotNull(customerFirst, customerLast).joinToString(" ").ifBlank { "Unknown" }
}

// ─── L726 — Device history entry ─────────────────────────────────────────────

/**
 * Single row from GET /api/v1/tickets/device-history.
 *
 * Server returns a plain JSON array as [data]; Retrofit receives
 * ApiResponse<List<DeviceHistoryEntry>>. [DeviceHistoryData] is kept as a
 * shim so the existing TicketDetailScreen call site does not require changes.
 */
data class DeviceHistoryEntry(
    @SerializedName("id")
    val id: Long = 0,
    @SerializedName("ticket_id")
    val ticketId: Long,
    @SerializedName("order_id")
    val orderId: String?,
    @SerializedName("device_name")
    val deviceName: String?,
    val imei: String?,
    val serial: String?,
    @SerializedName("device_type")
    val deviceType: String?,
    @SerializedName("customer_first")
    val customerFirst: String?,
    @SerializedName("customer_last")
    val customerLast: String?,
    @SerializedName("status_name")
    val statusName: String?,
    @SerializedName("status_color")
    val statusColor: String?,
    @SerializedName("status_is_closed")
    val statusIsClosed: Int?,
    @SerializedName("created_at")
    val createdAt: String?,
    // Legacy fields kept so TicketWarrantyDialog / DeviceHistorySheet callers compile
    @SerializedName("customer_name")
    val customerName: String? = null,
    @SerializedName("service_name")
    val serviceName: String? = null,
) {
    val displayCustomerName: String
        get() = customerName ?: listOfNotNull(customerFirst, customerLast).joinToString(" ").ifBlank { null } ?: "Unknown"
}

/**
 * Shim wrapper kept so TicketDetailViewModel compiles unchanged.
 * The getDeviceHistory endpoint now returns ApiResponse<List<DeviceHistoryEntry>>;
 * wrap the flat list in this class on the call site.
 */
data class DeviceHistoryData(
    val history: List<DeviceHistoryEntry>,
)

// ─── L727 — Pin to dashboard response ────────────────────────────────────────

data class PinDashboardResponse(
    @SerializedName("is_pinned")
    val isPinned: Boolean?,
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
