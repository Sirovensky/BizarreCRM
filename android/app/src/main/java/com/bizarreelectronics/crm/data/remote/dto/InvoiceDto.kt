package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

data class InvoiceListItem(
    val id: Long,
    @SerializedName("order_id")
    val orderId: String?,
    @SerializedName("customer_id")
    val customerId: Long?,
    // Server returns separate name fields from JOIN
    @SerializedName("first_name")
    val firstName: String?,
    @SerializedName("last_name")
    val lastName: String?,
    val organization: String?,
    @SerializedName("customer_phone")
    val customerPhone: String?,
    @SerializedName("ticket_id")
    val ticketId: Long?,
    @SerializedName("ticket_order_id")
    val ticketOrderId: String?,
    val subtotal: Double?,
    val discount: Double?,
    @SerializedName("total_tax")
    val totalTax: Double?,
    val total: Double?,
    val status: String?,
    @SerializedName("amount_paid")
    val amountPaid: Double?,
    @SerializedName("amount_due")
    val amountDue: Double?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("due_on")
    val dueOn: String?,
) {
    val customerName: String
        get() = listOfNotNull(firstName, lastName).joinToString(" ").ifBlank { organization ?: "Unknown" }
}

data class InvoiceDetail(
    val id: Long,
    @SerializedName("order_id")
    val orderId: String?,
    @SerializedName("customer_id")
    val customerId: Long?,
    // Server returns flat customer fields from JOIN, not nested object
    @SerializedName("first_name")
    val firstName: String?,
    @SerializedName("last_name")
    val lastName: String?,
    @SerializedName("customer_email")
    val customerEmail: String?,
    @SerializedName("customer_phone")
    val customerPhone: String?,
    val organization: String?,
    @SerializedName("created_by_name")
    val createdByName: String?,
    @SerializedName("ticket_id")
    val ticketId: Long?,
    @SerializedName("ticket_order_id")
    val ticketOrderId: String?,
    val subtotal: Double?,
    val discount: Double?,
    @SerializedName("discount_reason")
    val discountReason: String?,
    @SerializedName("total_tax")
    val totalTax: Double?,
    val total: Double?,
    val status: String?,
    @SerializedName("amount_paid")
    val amountPaid: Double?,
    @SerializedName("amount_due")
    val amountDue: Double?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
    @SerializedName("due_on")
    val dueOn: String?,
    @SerializedName("created_by")
    val createdBy: Long?,
    @SerializedName("line_items")
    val lineItems: List<InvoiceLineItem>?,
    val payments: List<InvoicePayment>?,
) {
    val customerName: String
        get() = listOfNotNull(firstName, lastName).joinToString(" ").ifBlank { organization ?: "Unknown" }
}

data class InvoiceLineItem(
    val id: Long,
    @SerializedName("invoice_id")
    val invoiceId: Long?,
    @SerializedName("inventory_item_id")
    val inventoryItemId: Long?,
    val name: String?,
    val sku: String?,
    val description: String?,
    val quantity: Int?,
    val price: Double?,
    @SerializedName("line_discount")
    val lineDiscount: Double?,
    val tax: Double?,
    @SerializedName("tax_class_id")
    val taxClassId: Long?,
    val total: Double?
)

data class InvoicePayment(
    val id: Long,
    @SerializedName("invoice_id")
    val invoiceId: Long?,
    val amount: Double?,
    val method: String?,
    @SerializedName("payment_date")
    val paymentDate: String?,
    @SerializedName("transaction_id")
    val transactionId: String?,
    val notes: String?,
    val type: String?,
    val status: String?
)

data class RecordPaymentRequest(
    val amount: Double,
    val method: String = "cash",
    @SerializedName("method_detail")
    val methodDetail: String? = null,
    val notes: String? = null,
    @SerializedName("transaction_id")
    val transactionId: String? = null
)

// ── Invoice creation DTOs ────────────────────────────────────────────────────

/**
 * Line-item shape for POST /invoices.
 * Server accepts `name`, `description`, `quantity`, `unit_price`, and an optional
 * `tax_class_id`. Tax is recomputed server-side when `tax_class_id` is present.
 */
data class CreateLineItemDto(
    val name: String,
    val description: String? = null,
    val quantity: Int = 1,
    @SerializedName("unit_price")
    val unitPrice: Double,
    @SerializedName("tax_class_id")
    val taxClassId: Long? = null,
)

/**
 * Request body for POST /invoices.
 * Matches server destructure: customer_id, ticket_id, line_items[], notes, due_date.
 * `discount` and `discount_reason` are intentionally omitted in this wave.
 */
data class CreateInvoiceRequest(
    @SerializedName("customer_id")
    val customerId: Long,
    @SerializedName("ticket_id")
    val ticketId: Long? = null,
    @SerializedName("line_items")
    val lineItems: List<CreateLineItemDto>,
    val notes: String? = null,
    @SerializedName("due_date")
    val dueDate: String? = null,
)

// ── Stats DTO ────────────────────────────────────────────────────────────────

/**
 * Aggregate invoice totals returned by GET /invoices/stats.
 * All amounts are in dollars (server returns doubles).
 * 404 → tolerated; UI skips the stats header.
 */
data class InvoiceStatsData(
    @SerializedName("total_unpaid")
    val totalUnpaid: Double = 0.0,
    @SerializedName("total_paid")
    val totalPaid: Double = 0.0,
    @SerializedName("total_overdue")
    val totalOverdue: Double = 0.0,
    @SerializedName("count_unpaid")
    val countUnpaid: Int = 0,
    @SerializedName("count_overdue")
    val countOverdue: Int = 0,
)

// ── Refund DTO ───────────────────────────────────────────────────────────────

/**
 * Request body for POST /refunds.
 */
data class IssueRefundRequest(
    @SerializedName("invoice_id")
    val invoiceId: Long,
    val amount: Double,
    val reason: String? = null,
)

// ── Credit Note DTO ──────────────────────────────────────────────────────────

/**
 * Request body for POST /invoices/:id/credit-note.
 * Server requires both `amount` (positive double) and `reason` (non-blank).
 */
data class CreditNoteRequest(
    val amount: Double,
    val reason: String,
)

/**
 * Response data envelope for POST /invoices/:id/credit-note.
 * Server returns the newly-created credit-note invoice.
 */
data class CreditNoteResponseData(
    @SerializedName("credit_note")
    val creditNote: InvoiceDetail? = null,
)

// ── Aging Report DTOs ────────────────────────────────────────────────────────

data class AgingBucket(
    val count: Int = 0,
    @SerializedName("total_cents")
    val totalCents: Long = 0L,
)

data class AgingInvoiceRow(
    val id: Long,
    @SerializedName("order_id")
    val orderId: String?,
    @SerializedName("customer_id")
    val customerId: Long?,
    @SerializedName("customer_name")
    val customerName: String?,
    @SerializedName("amount_due_cents")
    val amountDueCents: Long,
    @SerializedName("days_overdue")
    val daysOverdue: Int,
    val bucket: String,
)

data class AgingReportData(
    val buckets: Map<String, AgingBucket> = emptyMap(),
    val invoices: List<AgingInvoiceRow> = emptyList(),
)
