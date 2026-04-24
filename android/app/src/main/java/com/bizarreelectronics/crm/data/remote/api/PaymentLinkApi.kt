package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.QueryMap

/**
 * §41 — Payment Links API.
 *
 * All endpoints tolerate 404 — callers catch [retrofit2.HttpException] with
 * code 404 and display a "Payment links not configured on this server" stub.
 *
 * Response shape: ApiResponse<T> where T is defined below.
 */
interface PaymentLinkApi {

    /**
     * Create a new payment link.
     *
     * POST /payment-links
     * Body: { amount_cents, customer_id?, memo?, expires_at?, max_uses?, partial_allowed }
     * Response: { id, url, short_url, status, created_at }
     * 404 → endpoint not deployed; caller shows stub.
     */
    @POST("payment-links")
    suspend fun createLink(@Body request: CreatePaymentLinkRequest): ApiResponse<PaymentLinkData>

    /**
     * List existing payment links.
     *
     * GET /payment-links?status=pending|paid|expired|cancelled&customer_id=...
     * Response: { items: [...], total }
     * 404 → empty list stub.
     */
    @GET("payment-links")
    suspend fun listLinks(
        @QueryMap filters: Map<String, String> = emptyMap(),
    ): ApiResponse<PaymentLinkListData>

    /**
     * Poll current status of a specific payment link.
     *
     * GET /payment-links/:id/status
     * Response: { id, status, paid_at? }
     * 404 → caller keeps last known status.
     */
    @GET("payment-links/{id}/status")
    suspend fun getLinkStatus(@Path("id") id: Long): ApiResponse<PaymentLinkStatusData>

    /**
     * Void a payment link (cancel it before it expires).
     *
     * POST /payment-links/:id/void
     * 404 → endpoint not deployed; caller shows stub.
     */
    @POST("payment-links/{id}/void")
    suspend fun voidLink(@Path("id") id: Long): ApiResponse<Unit>

    /**
     * Resend the payment-request SMS / email to the customer.
     *
     * POST /payment-links/:id/resend
     * 404 → tolerated silently.
     */
    @POST("payment-links/{id}/resend")
    suspend fun resendLink(@Path("id") id: Long): ApiResponse<Unit>

    /**
     * Send a payment-request push to the customer (§41.4).
     *
     * POST /payment-links/:id/remind
     * 404 → tolerated silently.
     */
    @POST("payment-links/{id}/remind")
    suspend fun remindCustomer(@Path("id") id: Long): ApiResponse<Unit>
}

// ── Request / Response DTOs ──────────────────────────────────────────────────

data class CreatePaymentLinkRequest(
    val amount_cents: Long,
    val customer_id: Long? = null,
    val memo: String? = null,
    val expires_at: String? = null,   // ISO-8601
    val max_uses: Int? = null,
    val partial_allowed: Boolean = false,
)

data class PaymentLinkData(
    val id: Long,
    val url: String,
    val short_url: String = url,
    val status: String,               // pending | paid | expired | cancelled
    val amount_cents: Long,
    val memo: String?,
    val customer_id: Long?,
    val customer_name: String?,
    val expires_at: String?,
    val created_at: String,
    val paid_at: String?,
)

data class PaymentLinkListData(
    val items: List<PaymentLinkData>,
    val total: Int,
)

data class PaymentLinkStatusData(
    val id: Long,
    val status: String,
    val paid_at: String?,
)
