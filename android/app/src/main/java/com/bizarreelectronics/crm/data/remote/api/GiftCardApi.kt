package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path

// ─── DTOs ────────────────────────────────────────────────────────────────────

data class GiftCard(
    val id: Long,
    val code: String,
    @SerializedName("balance_cents")   val balanceCents: Long,
    @SerializedName("issued_cents")    val issuedCents: Long,
    @SerializedName("customer_id")     val customerId: Long?,
    @SerializedName("customer_name")   val customerName: String?,
    val status: String,                // "active" | "depleted" | "expired" | "voided"
    @SerializedName("expires_at")      val expiresAt: String?,
    @SerializedName("issued_at")       val issuedAt: String?,
)

data class GiftCardData(val card: GiftCard)

data class IssueGiftCardRequest(
    val code: String?,                           // null → server auto-generates
    @SerializedName("amount_cents")   val amountCents: Long,
    @SerializedName("customer_id")    val customerId: Long? = null,
    @SerializedName("send_digital")   val sendDigital: Boolean = false,
)

data class RedeemGiftCardRequest(
    val code: String,
    @SerializedName("amount_cents") val amountCents: Long,
)

data class GiftCardRedeemData(
    val card: GiftCard,
    @SerializedName("applied_cents")   val appliedCents: Long,
    @SerializedName("remaining_cents") val remainingCents: Long,
)

data class ReloadGiftCardRequest(
    @SerializedName("amount_cents") val amountCents: Long,
)

// ─── Store-credit DTOs ───────────────────────────────────────────────────────

data class StoreCredit(
    @SerializedName("customer_id")     val customerId: Long,
    @SerializedName("balance_cents")   val balanceCents: Long,
    @SerializedName("updated_at")      val updatedAt: String?,
)

data class StoreCreditData(val credit: StoreCredit)

data class IssueCreditRequest(
    @SerializedName("amount_cents") val amountCents: Long,
    val reason: String,
)

// ─── API interface ────────────────────────────────────────────────────────────

/**
 * Gift card issuance, redemption, reload, and per-customer store-credit endpoints.
 *
 * All endpoints are 404-tolerant — callers catch [retrofit2.HttpException] with
 * code 404 and degrade gracefully.
 *
 * Plan §40 L3060-L3086.
 */
interface GiftCardApi {

    /** Look up a gift card by code / barcode (§40.1). */
    @GET("gift-cards/{code}")
    suspend fun getGiftCard(@Path("code") code: String): ApiResponse<GiftCardData>

    /** Issue a new gift card (§40.1). */
    @POST("gift-cards")
    suspend fun issueGiftCard(@Body request: IssueGiftCardRequest): ApiResponse<GiftCardData>

    /** Redeem an amount from a gift card (§40.1). */
    @POST("gift-cards/redeem")
    suspend fun redeemGiftCard(@Body request: RedeemGiftCardRequest): ApiResponse<GiftCardRedeemData>

    /** Reload / add value to an existing gift card (§40.1). */
    @POST("gift-cards/{code}/reload")
    suspend fun reloadGiftCard(
        @Path("code") code: String,
        @Body request: ReloadGiftCardRequest,
    ): ApiResponse<GiftCardData>

    /** Get store-credit balance for a customer (§40.2). */
    @GET("store-credit/{customerId}")
    suspend fun getStoreCredit(@Path("customerId") customerId: Long): ApiResponse<StoreCreditData>

    /** Issue store credit to a customer (§40.2). */
    @POST("store-credit/{customerId}")
    suspend fun issueStoreCredit(
        @Path("customerId") customerId: Long,
        @Body request: IssueCreditRequest,
    ): ApiResponse<StoreCreditData>
}
