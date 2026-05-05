package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST

// ─── Request / Response DTOs ─────────────────────────────────────────────────

// 2026-04-26 — server contract names (matches POST /pos/sales handler):
//   items[].inventory_item_id, items[].quantity, payment_amount (dollars),
//   discount (dollars), tip (dollars). Previous Android schema (lines/item_id/
//   qty/cents) drifted from web and the server rejected with 400 "No items
//   in cart" because it destructured `items` not `lines`.
data class PosCartLineDto(
    val id: String,
    val type: String,              // "inventory" | "service" | "custom"
    @SerializedName("inventory_item_id") val itemId: Long?,
    val name: String,
    @SerializedName("quantity") val qty: Int,
    @SerializedName("unit_price_cents") val unitPriceCents: Long,
    @SerializedName("discount_cents") val discountCents: Long = 0L,
    @SerializedName("tax_class_id") val taxClassId: Long? = null,
    @SerializedName("tax_rate") val taxRate: Double = 0.0,
    val notes: String? = null,
)

data class PosSaleRequest(
    @SerializedName("idempotency_key") val idempotencyKey: String,
    @SerializedName("customer_id") val customerId: Long?,
    @SerializedName("items") val lines: List<PosCartLineDto>,
    /** dollars — server validatePrice. Convert from cents at call site. */
    @SerializedName("discount") val discount: Double = 0.0,
    @SerializedName("tip") val tip: Double = 0.0,
    @SerializedName("payment_method") val paymentMethod: String,
    /** dollars — server validates payment_amount as dollars. */
    @SerializedName("payment_amount") val paymentAmount: Double,
    val payments: List<PosPaymentDto>? = null,
    @SerializedName("linked_ticket_id") val linkedTicketId: Long? = null,
    val notes: String? = null,
    @SerializedName("tax_breakdown") val taxBreakdown: Map<String, Long>? = null,
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

/**
 * Loyalty-points redemption request (§38.6 / §38.3 POS integration).
 *
 * NOTE: server has no `/memberships/:id/redeem-points` endpoint yet — this DTO
 * is defined for when the endpoint is added. Redemption is currently applied
 * client-side as a `loyalty_points` tender; the server ignores unknown tender
 * methods and records it in the payments array. Full server-side point
 * deduction requires a new migration + endpoint (see TODO §38.6).
 */
data class PosLoyaltyRedeemRequest(
    @SerializedName("membership_id") val membershipId: Long,
    @SerializedName("points_to_redeem") val pointsToRedeem: Int,
    @SerializedName("amount_cents") val amountCents: Long,
)

data class QuickAddItem(
    val id: Long,
    val name: String,
    val sku: String? = null,
    @SerializedName("price_cents") val priceCents: Long,
    @SerializedName("photo_url") val photoUrl: String? = null,
    val type: String = "inventory",
    /** MVP category for filter chips: "Parts" | "Services" | "Accessories" | "Refurbished". Null = uncategorized. */
    val category: String? = null,
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
