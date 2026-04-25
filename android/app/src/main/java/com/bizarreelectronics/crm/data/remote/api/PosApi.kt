package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST

// ─── Request / Response DTOs ─────────────────────────────────────────────────

data class PosCartLineDto(
    val id: String,
    val type: String,              // "inventory" | "service" | "custom"
    @SerializedName("item_id") val itemId: Long?,
    val name: String,
    val qty: Int,
    @SerializedName("unit_price_cents") val unitPriceCents: Long,
    @SerializedName("discount_cents") val discountCents: Long = 0L,
    @SerializedName("tax_class_id") val taxClassId: Long? = null,
    @SerializedName("tax_rate") val taxRate: Double = 0.0,
    // POS-NOTES-001: server INSERT now includes notes column; max 1000 chars.
    val notes: String? = null,
)

data class PosSaleRequest(
    @SerializedName("idempotency_key") val idempotencyKey: String,
    @SerializedName("customer_id") val customerId: Long?,
    val lines: List<PosCartLineDto>,
    @SerializedName("cart_discount_cents") val cartDiscountCents: Long = 0L,
    @SerializedName("tip_cents") val tipCents: Long = 0L,
    @SerializedName("payment_method") val paymentMethod: String,
    @SerializedName("payment_amount_cents") val paymentAmountCents: Long,
    /** Multi-tender split: server prefers this when non-empty over the single
     *  payment_method/payment_amount_cents pair. */
    val payments: List<PosPaymentDto>? = null,
    /** When the cashier finalizes a Ready-for-pickup ticket the resulting
     *  invoice gets attached so it shows up in the ticket's history. */
    @SerializedName("linked_ticket_id") val linkedTicketId: Long? = null,
    val notes: String? = null,
)

data class PosPaymentDto(
    val method: String,                                  // 'cash' | 'card' | 'ach' | 'store_credit' | 'gift'
    @SerializedName("amount_cents") val amountCents: Long,
    val processor: String? = null,
    val reference: String? = null,
    @SerializedName("transaction_id") val transactionId: String? = null,
)

data class PosSaleData(
    @SerializedName("invoice_id") val invoiceId: Long,
    @SerializedName("order_id") val orderId: String,
    @SerializedName("change_cents") val changeCents: Long = 0L,
    @SerializedName("approval_code") val approvalCode: String? = null,
    @SerializedName("last_four") val lastFour: String? = null,
    /** Server-supplied absolute tracking URL (POS-RECEIPT-001). Null until deployed. */
    @SerializedName("tracking_url") val trackingUrl: String? = null,
)

data class PosInvoiceLaterRequest(
    @SerializedName("idempotency_key") val idempotencyKey: String,
    @SerializedName("customer_id") val customerId: Long?,
    val lines: List<PosCartLineDto>,
    @SerializedName("cart_discount_cents") val cartDiscountCents: Long = 0L,
    @SerializedName("tip_cents") val tipCents: Long = 0L,
    @SerializedName("due_on") val dueOn: String? = null,
    val notes: String? = null,
)

data class PosGiftCardRedeemRequest(
    val code: String,
    @SerializedName("amount_cents") val amountCents: Long,
)

data class PosGiftCardData(
    @SerializedName("balance_cents") val balanceCents: Long,
    @SerializedName("applied_cents") val appliedCents: Long,
    @SerializedName("remaining_cents") val remainingCents: Long,
)

data class QuickAddItem(
    val id: Long,
    val name: String,
    val sku: String? = null,
    @SerializedName("price_cents") val priceCents: Long,
    @SerializedName("photo_url") val photoUrl: String? = null,
    val type: String = "inventory",
)

data class QuickAddData(val items: List<QuickAddItem>)

// ─── API interface ────────────────────────────────────────────────────────────

/**
 * POS sale and cart endpoints.
 *
 * All endpoints are 404-tolerant at the call site — callers catch
 * [retrofit2.HttpException] with 404 and degrade gracefully.
 *
 * Plan §16.1 L1784-L1812.
 */
interface PosApi {

    /**
     * Complete a POS sale. Idempotency-Key (L1812) prevents double-charge on
     * retry. Header is sent as a custom header per-request.
     */
    @POST("pos/sales")
    suspend fun completeSale(
        @Header("Idempotency-Key") idempotencyKey: String,
        @Body request: PosSaleRequest,
    ): ApiResponse<PosSaleData>

    /**
     * Create an invoice-later (L1811) — no payment captured now.
     */
    @POST("pos/invoice-later")
    suspend fun createInvoiceLater(
        @Header("Idempotency-Key") idempotencyKey: String,
        @Body request: PosInvoiceLaterRequest,
    ): ApiResponse<PosSaleData>

    /**
     * Redeem a gift card (L1808). Returns new balance and amount applied.
     */
    @POST("gift-cards/redeem")
    suspend fun redeemGiftCard(
        @Body request: PosGiftCardRedeemRequest,
    ): ApiResponse<PosGiftCardData>

    /**
     * Quick-add catalog tiles for the cart screen Catalog tab. Returns
     * Today's Top-5 sold inventory items, falling back to first 10 active
     * items when there are no sales yet today. Server endpoint:
     * /api/v1/pos-enrich/quick-add (server posEnrich.routes.ts).
     */
    @GET("pos-enrich/quick-add")
    suspend fun getQuickAddItems(): ApiResponse<QuickAddData>
}
