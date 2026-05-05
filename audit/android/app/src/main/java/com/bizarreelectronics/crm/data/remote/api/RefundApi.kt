package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

// ─── DTOs ────────────────────────────────────────────────────────────────────

data class RefundRow(
    val id: Long,
    @SerializedName("invoice_id")     val invoiceId: Long?,
    @SerializedName("ticket_id")      val ticketId: Long?,
    @SerializedName("customer_id")    val customerId: Long,
    /** Server stores as floating-point dollars; multiply × 100 for cents. */
    val amount: Double,
    /** "refund" | "store_credit" | "credit_note" */
    val type: String,
    val reason: String?,
    /** "cash" | "card" | "gift_card" | "store_credit" | … */
    val method: String?,
    /** "pending" | "completed" | "declined" */
    val status: String,
    @SerializedName("created_at")     val createdAt: String?,
    @SerializedName("first_name")     val firstName: String?,
    @SerializedName("last_name")      val lastName: String?,
)

data class RefundListData(
    val refunds: List<RefundRow>,
)

data class CreateRefundRequest(
    @SerializedName("invoice_id")  val invoiceId: Long?,
    @SerializedName("ticket_id")   val ticketId: Long?,
    @SerializedName("customer_id") val customerId: Long,
    /** Amount in dollars (server validates positive amount). */
    val amount: Double,
    /** "refund" | "store_credit" | "credit_note" */
    val type: String = "refund",
    val reason: String? = null,
    /** Refund-back method; "card" routes through BlockChyp reverse. */
    val method: String? = null,
)

data class CreateRefundData(val id: Long)

data class GiftCardSummary(
    @SerializedName("total_cards")      val totalCards: Int,
    @SerializedName("total_outstanding") val totalOutstanding: Double,
    @SerializedName("active_count")     val activeCount: Int,
)

data class GiftCardListData(
    val cards: List<GiftCard>,
    val summary: GiftCardSummary?,
)

// ─── API interface ────────────────────────────────────────────────────────────

/**
 * Refund lifecycle + gift-card liability endpoints.
 *
 * §40.3: POST /refunds (create), PATCH /refunds/:id/approve, PATCH /refunds/:id/decline.
 * §40.4: GET /gift-cards (summary.total_outstanding), GET /store-credit/liability.
 *
 * All 404-tolerant — callers degrade gracefully on missing server routes.
 */
interface RefundApi {

    /** List refunds (paginated). §40.3. */
    @GET("refunds")
    suspend fun listRefunds(
        @Query("page") page: Int = 1,
        @Query("pagesize") pageSize: Int = 25,
    ): ApiResponse<RefundListData>

    /**
     * Create a new pending refund. Requires admin/manager role on server.
     * §40.3 — original-tender path + store-credit alternative.
     */
    @POST("refunds")
    suspend fun createRefund(@Body request: CreateRefundRequest): ApiResponse<CreateRefundData>

    /**
     * Approve a pending refund (admin only).
     * Server atomically decrements invoice.amount_paid and optionally posts
     * store credit if type = "store_credit".
     */
    @PATCH("refunds/{id}/approve")
    suspend fun approveRefund(@Path("id") id: Long): ApiResponse<CreateRefundData>

    /** Decline a pending refund (admin only). */
    @PATCH("refunds/{id}/decline")
    suspend fun declineRefund(@Path("id") id: Long): ApiResponse<CreateRefundData>

    /**
     * Gift-card list with liability summary.
     * §40.4 — [GiftCardSummary.totalOutstanding] is the total outstanding
     * gift-card liability owed to customers.
     */
    @GET("gift-cards")
    suspend fun listGiftCards(
        @Query("status") status: String? = null,
        @Query("page") page: Int = 1,
        @Query("per_page") perPage: Int = 50,
    ): ApiResponse<GiftCardListData>
}
