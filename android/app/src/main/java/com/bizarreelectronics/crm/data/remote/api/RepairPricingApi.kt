package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.*
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * RepairPricingApi — §4.9 L766
 *
 * Retrofit interface for the repair pricing catalog. Exposes the searchable
 * services list with per-device-model labor rate overrides.
 *
 * iOS parallel: same endpoints consumed by the iOS Swift client via URLSession.
 *
 * Server endpoints (packages/server/src/routes/repair-pricing.ts):
 *   GET  /api/v1/repair-pricing/services
 *   POST /api/v1/repair-pricing/services
 *   PUT  /api/v1/repair-pricing/services/:id
 *   GET  /api/v1/repair-pricing/lookup
 *
 * All endpoints are 404-tolerant: callers catch [retrofit2.HttpException] with
 * code 404 and fall back gracefully (empty list / no-op).
 */
interface RepairPricingApi {

    /**
     * Fetch the full services catalog, optionally filtered by [query] or [category].
     *
     * @param query    Optional free-text search term matched against service name.
     * @param category Optional category slug filter.
     * @return list of [RepairServiceItem].
     */
    @GET("repair-pricing/services")
    suspend fun getServices(
        @Query("q") query: String? = null,
        @Query("category") category: String? = null,
    ): ApiResponse<List<RepairServiceItem>>

    /**
     * Look up labor rate for a specific service + device model combination.
     *
     * @param deviceModelId Device model ID for per-model override lookup.
     * @param serviceId     Repair service ID.
     * @return [RepairPriceLookup] with base rate + grade overrides.
     */
    @GET("repair-pricing/lookup")
    suspend fun pricingLookup(
        @Query("device_model_id") deviceModelId: Int,
        @Query("repair_service_id") serviceId: Int,
    ): ApiResponse<RepairPriceLookup>

    /**
     * Create a new service entry in the pricing catalog.
     *
     * @param body [UpsertRepairServiceRequest] with name, category, and default labor rate.
     * @return the newly created [RepairServiceItem].
     */
    @POST("repair-pricing/services")
    suspend fun createService(@Body body: UpsertRepairServiceRequest): ApiResponse<RepairServiceItem>

    /**
     * Update an existing service in the pricing catalog.
     *
     * @param id   Service ID to update.
     * @param body Fields to overwrite.
     * @return the updated [RepairServiceItem].
     */
    @PUT("repair-pricing/services/{id}")
    suspend fun updateService(
        @Path("id") id: Long,
        @Body body: UpsertRepairServiceRequest,
    ): ApiResponse<RepairServiceItem>
}

// ─── Request DTO ─────────────────────────────────────────────────────────────

/**
 * Request body for POST/PUT repair-pricing/services.
 * [slug] is required on POST (auto-generated from name); may be null on PUT.
 */
data class UpsertRepairServiceRequest(
    val name: String,
    val slug: String?,
    val category: String?,
    @SerializedName("labor_price")
    val laborPrice: Double,
    @SerializedName("is_active")
    val isActive: Int = 1,
) {
    companion object {
        /** Convert a display name to a URL-safe slug (lowercase, hyphens). */
        fun slugify(name: String): String =
            name.trim().lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-')
    }
}
