package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

// ---------------------------------------------------------------------------
// §55 — Public tracking portal DTOs
//
// Maps the server's GET /api/v1/track/portal/:orderId response shape.
// Only customer-visible fields are present; cost breakdowns, internal
// notes, and technician names are stripped server-side (§55.4).
// ---------------------------------------------------------------------------

/** Status summary returned by the public portal. */
data class PublicTicketStatus(
    val name: String?,
    val color: String?,
    @SerializedName("is_closed")
    val isClosed: Boolean,
)

/** Device summary visible to the customer. */
data class PublicTicketDevice(
    val name: String?,
    val type: String?,
    val status: String?,
    @SerializedName("due_on")
    val dueOn: String?,
    val notes: String?,
)

/** A single customer-visible history entry (status transitions only). */
data class PublicTicketHistoryEntry(
    val action: String?,
    val description: String?,
    @SerializedName("old_value")
    val oldValue: String?,
    @SerializedName("new_value")
    val newValue: String?,
    @SerializedName("created_at")
    val createdAt: String?,
)

/** Public-facing invoice summary (totals only, no line-item detail). */
data class PublicTicketInvoice(
    @SerializedName("order_id")
    val orderId: String?,
    val status: String?,
    val subtotal: Double?,
    val discount: Double?,
    val tax: Double?,
    val total: Double?,
    @SerializedName("amount_paid")
    val amountPaid: Double?,
    @SerializedName("amount_due")
    val amountDue: Double?,
)

/** Store contact info returned alongside ticket data. */
data class PublicStoreInfo(
    @SerializedName("store_name")
    val storeName: String?,
    @SerializedName("store_phone")
    val storePhone: String?,
    @SerializedName("store_email")
    val storeEmail: String?,
    @SerializedName("store_address")
    val storeAddress: String?,
    @SerializedName("store_city")
    val storeCity: String?,
    @SerializedName("store_state")
    val storeState: String?,
    @SerializedName("store_zip")
    val storeZip: String?,
)

/**
 * Full customer-portal payload from GET /api/v1/track/portal/:orderId.
 *
 * The [store] field is a key→value map on the wire; we keep it as a Map
 * here and expose a [toStoreInfo] helper so callers avoid manual key
 * extraction.
 */
data class PublicTicketData(
    @SerializedName("order_id")
    val orderId: String?,
    val status: PublicTicketStatus?,
    @SerializedName("customer_first_name")
    val customerFirstName: String?,
    @SerializedName("due_on")
    val dueOn: String?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
    val devices: List<PublicTicketDevice>?,
    val history: List<PublicTicketHistoryEntry>?,
    val messages: List<PublicTicketMessage>?,
    val invoice: PublicTicketInvoice?,
    /** Raw key→value map from store_config. Use [toStoreInfo] for typed access. */
    val store: Map<String, String>?,
) {
    fun toStoreInfo(): PublicStoreInfo? {
        val m = store ?: return null
        return PublicStoreInfo(
            storeName    = m["store_name"],
            storePhone   = m["store_phone"],
            storeEmail   = m["store_email"],
            storeAddress = m["store_address"],
            storeCity    = m["store_city"],
            storeState   = m["store_state"],
            storeZip     = m["store_zip"],
        )
    }
}

/** Customer-visible message from/to the shop (type = 'customer' notes only). */
data class PublicTicketMessage(
    val id: Long?,
    val content: String?,
    val type: String?,
    val author: String?,
    @SerializedName("created_at")
    val createdAt: String?,
)
