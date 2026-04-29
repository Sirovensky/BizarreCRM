package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.DispatchJobDetail
import com.bizarreelectronics.crm.data.remote.dto.DispatchJobListData
import com.bizarreelectronics.crm.data.remote.dto.RouteOptimizeRequest
import com.bizarreelectronics.crm.data.remote.dto.RouteOptimizeResult
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.QueryMap

/**
 * Retrofit interface for Field Service / Dispatch endpoints.
 *
 * Base path: /api/v1/field-service  (mounted in server/src/index.ts line 1640)
 *
 * NOTE: server endpoints exist and are wired. No 404-tolerance needed.
 */
interface DispatchApi {

    /** GET /jobs  — technician sees only their own jobs; manager sees all */
    @GET("api/v1/field-service/jobs")
    suspend fun getJobs(
        @QueryMap options: Map<String, String> = emptyMap(),
    ): ApiResponse<DispatchJobListData>

    /** GET /jobs/:id */
    @GET("api/v1/field-service/jobs/{id}")
    suspend fun getJob(@Path("id") id: Long): ApiResponse<DispatchJobDetail>

    /**
     * POST /jobs/:id/status  — accept (assigned → en_route), start (en_route → on_site),
     * or complete (on_site → completed).
     * Body: { status, notes?, location_lat?, location_lng? }
     */
    @POST("api/v1/field-service/jobs/{id}/status")
    suspend fun updateJobStatus(
        @Path("id") id: Long,
        @Body body: Map<String, @JvmSuppressWildcards Any?>,
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any?>>

    /**
     * POST /routes/optimize  — §59.2 greedy nearest-neighbor route ordering.
     *
     * Manager / admin only (server enforces 403 for other roles).
     * Rate-limited: 10 requests per minute per user.
     *
     * Body: { technician_id, route_date (YYYY-MM-DD), job_ids: number[] }
     * Response data: { proposed_order: number[], total_distance_km: number,
     *                  algorithm: string, note: string, start_from_home: boolean }
     *
     * Does NOT persist — caller must apply the order locally.
     */
    @POST("api/v1/field-service/routes/optimize")
    suspend fun optimizeRoute(
        @Body request: RouteOptimizeRequest,
    ): ApiResponse<RouteOptimizeResult>

    /**
     * POST /jobs/:id/status with status=canceled — no separate cancel endpoint;
     * re-uses the same status transition endpoint.
     */
}
