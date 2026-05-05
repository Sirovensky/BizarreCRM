package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * §14.6 — Shift schedule endpoints.
 *
 * Mounted at /api/v1/schedule (see shiftsSchedule.routes.ts).
 *
 * GET  /schedule/shifts          — list shifts (filterable by week_start + user_id)
 * POST /schedule/shifts          — create a shift (manager/admin)
 * PATCH /schedule/shifts/:id     — edit a shift (manager/admin)
 * DELETE /schedule/shifts/:id    — delete a shift (manager/admin)
 *
 * All endpoints 404-tolerant — callers guard with runCatching.
 */
interface ShiftScheduleApi {

    /**
     * List shifts for the given week.
     * @param weekStart ISO date string for Monday of the desired week (YYYY-MM-DD).
     * @param userId    Optional — filter to a single employee.
     */
    @GET("schedule/shifts")
    suspend fun getShifts(
        @Query("week_start") weekStart: String? = null,
        @Query("user_id") userId: Long? = null,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Create a shift.
     * Body: { user_id, start_time, end_time, role?, notes? }
     */
    @POST("schedule/shifts")
    suspend fun createShift(
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Edit an existing shift.
     * Body: { start_time?, end_time?, role?, notes? }
     */
    @PATCH("schedule/shifts/{id}")
    suspend fun updateShift(
        @Path("id") shiftId: Long,
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /** Delete a shift. */
    @DELETE("schedule/shifts/{id}")
    suspend fun deleteShift(
        @Path("id") shiftId: Long,
    ): ApiResponse<@JvmSuppressWildcards Any>
}
