package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * §14.6 — Shift schedule API.
 *
 * Mounted at /api/v1/schedule on the server (shiftsSchedule.routes.ts).
 *
 * All write endpoints require manager or admin role.
 * GET /shifts is accessible to all authenticated users (non-managers see own shifts).
 */

data class ShiftDto(
    val id: Long,
    @SerializedName("user_id") val userId: Long,
    @SerializedName("start_at") val startAt: String,
    @SerializedName("end_at") val endAt: String,
    @SerializedName("role_tag") val roleTag: String?,
    @SerializedName("location_id") val locationId: Long?,
    val notes: String?,
    val status: String,
    @SerializedName("first_name") val firstName: String?,
    @SerializedName("last_name") val lastName: String?,
    val username: String?,
)

data class CreateShiftBody(
    @SerializedName("user_id") val userId: Long,
    @SerializedName("start_at") val startAt: String,
    @SerializedName("end_at") val endAt: String,
    @SerializedName("role_tag") val roleTag: String? = null,
    val notes: String? = null,
)

interface ShiftsApi {

    /**
     * List shifts.
     * [userId] — if provided and caller is manager, filters by employee.
     * [fromDate] / [toDate] — ISO 8601 date strings (e.g. "2026-04-21").
     * Returns { success, data: ShiftDto[] }
     */
    @GET("schedule/shifts")
    suspend fun getShifts(
        @Query("user_id") userId: Long? = null,
        @Query("from_date") fromDate: String? = null,
        @Query("to_date") toDate: String? = null,
    ): ApiResponse<List<ShiftDto>>

    /** Create a shift. Manager/admin only. */
    @POST("schedule/shifts")
    suspend fun createShift(
        @Body body: CreateShiftBody,
    ): ApiResponse<ShiftDto>

    /** Partial update — change start_at / end_at / notes. Manager/admin only. */
    @PATCH("schedule/shifts/{id}")
    suspend fun patchShift(
        @Path("id") shiftId: Long,
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<ShiftDto>

    /** Delete a shift. Manager/admin only. */
    @DELETE("schedule/shifts/{id}")
    suspend fun deleteShift(
        @Path("id") shiftId: Long,
    ): ApiResponse<@JvmSuppressWildcards Any>
}
