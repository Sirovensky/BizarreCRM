package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.CreateLocationRequest
import com.bizarreelectronics.crm.data.remote.dto.LocationDto
import com.bizarreelectronics.crm.data.remote.dto.UpdateLocationRequest
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * Retrofit interface for the multi-location management endpoints.
 *
 * ActionPlan §63 — Multi-Location Management.
 *
 * Mount point: GET|POST|PATCH|DELETE /api/v1/locations
 *
 * All endpoints are 404-tolerant — callers must handle 404 gracefully
 * (degrade to single-location mode, show "Locations not available" state).
 *
 * Role gates are enforced server-side:
 *   list / detail : any authenticated user
 *   create / patch / delete / set-default : admin only (server returns 403 otherwise)
 *
 * Registered in [com.bizarreelectronics.crm.data.remote.RetrofitClient.provideLocationApi].
 */
interface LocationApi {

    /**
     * List all locations.
     * Query param `active=1` restricts to active locations only.
     * Returns locations ordered by is_default DESC, name ASC.
     */
    @GET("locations")
    suspend fun getLocations(
        @Query("active") active: Int? = null,
    ): ApiResponse<List<LocationDto>>

    /**
     * Single location detail + user_count.
     * 404 when id does not exist.
     */
    @GET("locations/{id}")
    suspend fun getLocation(@Path("id") id: Long): ApiResponse<LocationDto>

    /**
     * Create a new location (admin only; 403 for non-admin).
     * Returns 201 with the newly created location.
     */
    @POST("locations")
    suspend fun createLocation(@Body request: CreateLocationRequest): ApiResponse<LocationDto>

    /**
     * Partial update for an existing location (admin only; 403 for non-admin).
     * Only the fields supplied in the request body are updated.
     */
    @PATCH("locations/{id}")
    suspend fun updateLocation(
        @Path("id") id: Long,
        @Body request: UpdateLocationRequest,
    ): ApiResponse<LocationDto>

    /**
     * Soft-deactivate a location (admin only).
     * Blocked server-side if: only one active location, or is_default=1.
     * Returns { id, is_active: 0 } on success.
     */
    @DELETE("locations/{id}")
    suspend fun deactivateLocation(@Path("id") id: Long): ApiResponse<Unit>

    /**
     * Set a location as the default (admin only).
     * Server atomically clears is_default on all other rows.
     * Idempotent — no-op if already default.
     */
    @POST("locations/{id}/set-default")
    suspend fun setDefault(@Path("id") id: Long): ApiResponse<LocationDto>

    /**
     * Convenience: resolve the current user's active work location.
     * Priority: users.home_location_id → user_locations.is_primary=1 → global default.
     * Returns null data when no location is configured.
     * 404-tolerant — callers degrade to no active location chip.
     */
    @GET("locations/me/default-location")
    suspend fun getMyDefaultLocation(): ApiResponse<LocationDto>
}
