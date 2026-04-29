package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.FieldServiceJobListData
import com.bizarreelectronics.crm.data.remote.dto.OptimizeRouteResponse
import com.bizarreelectronics.crm.data.remote.dto.UpdateDispatchJobRequest
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path

/**
 * FieldServiceApi — §59 Field-Service / Dispatch
 *
 * Retrofit interface for dispatch/field-service endpoints. All calls are
 * 404-tolerant: callers catch [retrofit2.HttpException] with code 404 and
 * degrade gracefully (empty job list, no-op route optimization).
 *
 * Server endpoints (packages/server/src/routes/dispatch.ts — not yet deployed):
 *   GET  /api/v1/dispatch/jobs                → list open + today's jobs
 *   PATCH /api/v1/dispatch/jobs/:id           → update job status / notes
 *   POST /api/v1/dispatch/optimize            → returns ordered job list
 */
interface FieldServiceApi {

    /**
     * Fetch the technician's current dispatch job list.
     *
     * @return [ApiResponse] wrapping [FieldServiceJobListData] with `jobs` list.
     *         Returns 404 when the server build pre-dates this endpoint;
     *         callers fall back to an empty list.
     */
    @GET("dispatch/jobs")
    suspend fun getJobs(): ApiResponse<FieldServiceJobListData>

    /**
     * Update a dispatch job's status or technician notes.
     *
     * @param jobId  The dispatch job ID to update.
     * @param body   [UpdateDispatchJobRequest] with status and/or notes fields.
     * @return [ApiResponse] wrapping the updated [FieldServiceJobListData.DispatchJob].
     */
    @PATCH("dispatch/jobs/{id}")
    suspend fun updateJob(
        @Path("id") jobId: Long,
        @Body body: UpdateDispatchJobRequest,
    ): ApiResponse<FieldServiceJobListData.DispatchJob>

    /**
     * Request a route-optimized ordering of today's jobs for this technician.
     *
     * @return [ApiResponse] wrapping [OptimizeRouteResponse] with an ordered
     *         list of job IDs. Returns 404 when the server build pre-dates
     *         this endpoint; callers fall back to the existing list order.
     */
    @POST("dispatch/optimize")
    suspend fun optimizeRoute(): ApiResponse<OptimizeRouteResponse>
}
