package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * §48.1 — Goals API
 *
 * Server endpoints:
 *   GET  /goals              — list goals for the current user (or all if manager)
 *   POST /goals              — create a new goal
 *   PUT  /goals/:id          — update progress/status
 *   DELETE /goals/:id        — remove a goal
 *
 * All endpoints are 404-tolerant: callers guard with runCatching or HttpException
 * catch and show an "not configured on this server" empty state on failure.
 */
interface GoalApi {

    /**
     * List goals. Pass [employeeId] to filter by a specific employee (manager only).
     * Returns { goals: [...] }.
     */
    @GET("goals")
    suspend fun getGoals(
        @Query("employee_id") employeeId: Long? = null,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Create a goal.
     * Body: { title, metric, target, period, employee_id? }
     */
    @POST("goals")
    suspend fun createGoal(
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Update a goal (progress, status, or metadata).
     * Body: partial — only send fields that changed.
     */
    @PUT("goals/{id}")
    suspend fun updateGoal(
        @Path("id") goalId: Long,
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Delete a goal by id.
     */
    @DELETE("goals/{id}")
    suspend fun deleteGoal(
        @Path("id") goalId: Long,
    ): ApiResponse<@JvmSuppressWildcards Any>
}
