package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path

// ─── DTOs ────────────────────────────────────────────────────────────────────

data class MembershipTier(
    val id: Long,
    val name: String,                          // "Basic" | "Silver" | "Gold"
    val description: String?,
    @SerializedName("monthly_price_cents") val monthlyPriceCents: Long,
    @SerializedName("annual_price_cents")  val annualPriceCents: Long,
    @SerializedName("discount_percent")    val discountPercent: Double = 0.0,
    @SerializedName("free_diagnostics")    val freeDiagnostics: Boolean = false,
    @SerializedName("priority_queue")      val priorityQueue: Boolean = false,
    @SerializedName("extended_warranty")   val extendedWarranty: Boolean = false,
)

data class MembershipTierListData(val tiers: List<MembershipTier>)

data class Membership(
    val id: Long,
    @SerializedName("customer_id")  val customerId: Long,
    @SerializedName("tier_id")      val tierId: Long,
    @SerializedName("tier_name")    val tierName: String?,
    val status: String,                        // "active" | "expired" | "cancelled"
    @SerializedName("started_at")   val startedAt: String?,
    @SerializedName("expires_at")   val expiresAt: String?,
    @SerializedName("renewal_date") val renewalDate: String?,
    @SerializedName("points")       val points: Int = 0,
    @SerializedName("benefit_uses") val benefitUses: Int = 0,
)

data class MembershipListData(val memberships: List<Membership>)

data class EnrollMemberRequest(
    @SerializedName("customer_id") val customerId: Long,
    @SerializedName("tier_id")     val tierId: Long,
    val billing: String,                       // "monthly" | "annual"
    @SerializedName("payment_method") val paymentMethod: String,
)

data class EnrollMemberData(val membership: Membership)

data class RenewMembershipData(val membership: Membership)

data class CancelMembershipData(val cancelled: Boolean, val immediate: Boolean)

// ─── API interface ────────────────────────────────────────────────────────────

/**
 * Memberships / Loyalty endpoints.
 *
 * All endpoints are 404-tolerant — callers catch [retrofit2.HttpException] with
 * code 404 and show "Not available on this server" rather than crashing.
 *
 * Plan §38 L2997-L3025.
 */
interface MembershipApi {

    /** List available membership tiers (§38.1). */
    @GET("memberships/tiers")
    suspend fun getTiers(): ApiResponse<MembershipTierListData>

    /** List all active memberships (§38.2). */
    @GET("memberships")
    suspend fun getMemberships(): ApiResponse<MembershipListData>

    /** Get a single membership by id (§38.2). */
    @GET("memberships/{id}")
    suspend fun getMembership(@Path("id") id: Long): ApiResponse<EnrollMemberData>

    /** Enroll a customer into a tier (§38.2). */
    @POST("memberships")
    suspend fun enroll(@Body request: EnrollMemberRequest): ApiResponse<EnrollMemberData>

    /** Renew an existing membership (§38.2). */
    @POST("memberships/{id}/renew")
    suspend fun renew(@Path("id") id: Long): ApiResponse<RenewMembershipData>

    /**
     * Cancel a membership (§38.2). [body] should contain `{"immediate": true/false}`.
     * Maps to `POST /memberships/:id/cancel`.
     */
    @POST("memberships/{id}/cancel")
    suspend fun cancel(
        @Path("id") id: Long,
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<CancelMembershipData>

    /**
     * Get the active membership for a specific customer (§38.2 / §38.3 TierChip in POS).
     * Maps to `GET /memberships/customer/:customerId`.
     */
    @GET("memberships/customer/{customerId}")
    suspend fun getCustomerMembership(@Path("customerId") customerId: Long): ApiResponse<EnrollMemberData>
}
