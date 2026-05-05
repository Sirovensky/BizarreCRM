package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * §48.3 — Time-Off Requests API
 *
 * Server endpoints:
 *   GET  /time-off           — list requests (manager: all pending; staff: own)
 *   POST /time-off           — staff submits a new request
 *   PUT  /time-off/:id       — manager approves/rejects; staff cancels own pending
 *
 * All endpoints are 404-tolerant; callers show "not configured on this server"
 * empty state on HttpException(404).
 */
interface TimeOffApi {

    /**
     * List time-off requests.
     * [status] filters by "pending" | "approved" | "rejected" | "cancelled".
     * [employeeId] filters by employee (manager use only).
     * Returns { requests: [...] }.
     */
    @GET("time-off")
    suspend fun getRequests(
        @Query("status") status: String? = null,
        @Query("employee_id") employeeId: Long? = null,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Submit a time-off request.
     * Body: { start_date, end_date, type, reason }
     * Types: vacation | sick | personal | unpaid
     */
    @POST("time-off")
    suspend fun submitRequest(
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Approve, reject, or cancel a request.
     * Body: { action: "approve"|"reject"|"cancel", reason? }
     */
    @PUT("time-off/{id}")
    suspend fun updateRequest(
        @Path("id") requestId: Long,
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<@JvmSuppressWildcards Any>
}
