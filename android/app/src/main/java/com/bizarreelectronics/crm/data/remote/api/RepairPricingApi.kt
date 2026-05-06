package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.*
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.DELETE
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
 *   POST /api/v1/repair-pricing/prices
 *   PUT  /api/v1/repair-pricing/prices/:id
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
     * Create a model-specific labor price for an existing service.
     *
     * Server contract: POST /api/v1/repair-pricing/prices with
     * { device_model_id, repair_service_id, labor_price }. The server defaults
     * is_custom=1 and returns the created repair_prices row.
     */
    @POST("repair-pricing/prices")
    suspend fun createPrice(@Body body: UpsertRepairPriceRequest): ApiResponse<RepairPriceLookup>

    /**
     * Update an existing model-specific labor price row. Used when lookup
     * returns a zero-price placeholder row for the selected model/service.
     */
    @PUT("repair-pricing/prices/{id}")
    suspend fun updatePrice(
        @Path("id") id: Long,
        @Body body: UpsertRepairPriceRequest,
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

    /**
     * Delete a service from the pricing catalog (admin/manager only).
     *
     * 404-tolerant: callers catch [retrofit2.HttpException] with code 404 and
     * treat the delete as a no-op (already gone).
     * 400 returned by server when service is still referenced by repair_prices rows.
     *
     * @param id Service ID to delete.
     */
    @DELETE("repair-pricing/services/{id}")
    suspend fun deleteService(@Path("id") id: Long): ApiResponse<Unit>

    /**
     * Apply a global bulk price adjustment to all services in the catalog.
     *
     * @param body [BulkPriceAdjustRequest] with flat and/or percentage delta.
     */
    @POST("repair-pricing/adjust")
    suspend fun bulkAdjust(@Body body: BulkPriceAdjustRequest): ApiResponse<Unit>
}

// ─── Request DTOs ─────────────────────────────────────────────────────────────

/**
 * Request body for POST/PUT repair-pricing/services.
 *
 * [laborPrice] is a plain Double on the wire (server stores as REAL), NOT cents.
 * The server uses REAL for repair_services.labor_price (legacy schema).
 */
data class UpsertRepairServiceRequest(
    val name: String,
    val slug: String? = null,
    val category: String?,
    val description: String? = null,
    @SerializedName("labor_price")
    val laborPrice: Double,
    @SerializedName("is_active")
    val isActive: Int = 1,
    @SerializedName("sort_order")
    val sortOrder: Int = 0,
)

/**
 * Request body for POST repair-pricing/adjust (bulk price adjustment, admin only).
 *
 * Either [flatAdjustment] or [pctAdjustment] (or both) must be non-zero.
 * Server applies: adjusted = base * (1 + pct/100) + flat.
 */
data class BulkPriceAdjustRequest(
    @SerializedName("flat_adjustment")
    val flatAdjustment: Double = 0.0,
    @SerializedName("pct_adjustment")
    val pctAdjustment: Double = 0.0,
)

/**
 * Request body for POST/PUT repair-pricing/prices.
 *
 * [laborPrice] is a plain Double on the wire (server stores as REAL), not cents.
 */
data class UpsertRepairPriceRequest(
    @SerializedName("device_model_id")
    val deviceModelId: Long,
    @SerializedName("repair_service_id")
    val repairServiceId: Long,
    @SerializedName("labor_price")
    val laborPrice: Double,
)
